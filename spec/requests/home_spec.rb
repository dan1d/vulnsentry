require "rails_helper"

RSpec.describe "Home", type: :request do
  it "shows empty state when no PRs" do
    get "/"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("No PRs tracked yet")
  end

  it "lists PRs with status, link, and proposed diff" do
    branch = create(:branch_target, name: "ruby_3_4", enabled: true, maintenance_status: "normal")
    advisory = create(:advisory, cve: "CVE-2026-0001", advisory_url: "https://example.test/advisory")
    bump = create(
      :candidate_bump,
      advisory: advisory,
      branch_target: branch,
      base_branch: "ruby_3_4",
      gem_name: "rexml",
      current_version: "3.4.4",
      target_version: "3.4.5",
      proposed_diff: "--- a/Gemfile\n+++ b/Gemfile\n@@\n- rexml (3.4.4)\n+ rexml (3.4.5)\n"
    )
    create(
      :pull_request,
      candidate_bump: bump,
      status: "merged",
      pr_number: 12_345,
      pr_url: "https://github.com/ruby/ruby/pull/12345"
    )
    bundle = create(
      :patch_bundle,
      branch_target: branch,
      base_branch: "ruby_3_4",
      gem_name: "rake",
      current_version: "13.2.0",
      target_version: "13.2.1",
      proposed_diff: "--- a/Gemfile.lock\n+++ b/Gemfile.lock\n@@\n- rake (13.2.0)\n+ rake (13.2.1)\n"
    )
    create(:pull_request, :for_patch_bundle, patch_bundle: bundle, status: "open", pr_number: 98_765)

    get "/"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Security PRs")
    expect(response.body).to include("https://github.com/ruby/ruby/pull/12345")
    expect(response.body).to include("merged")
    expect(response.body).to include("open")
    expect(response.body).to include("rexml")
    expect(response.body).to include("rake")
    expect(response.body).to include("+++ b/Gemfile")
    expect(response.body).to include("+++ b/Gemfile.lock")
  end
end
