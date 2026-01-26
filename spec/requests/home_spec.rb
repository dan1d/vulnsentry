require "rails_helper"

RSpec.describe "Home", type: :request do
  it "shows empty state when no merged PRs" do
    get "/"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("No merged PRs tracked yet")
  end

  it "lists merged PRs with links and descriptions" do
    branch = create(:branch_target, name: "ruby_3_4", enabled: true, maintenance_status: "normal")
    advisory = create(:advisory, cve: "CVE-2026-0001", advisory_url: "https://example.test/advisory")
    bump = create(
      :candidate_bump,
      advisory: advisory,
      branch_target: branch,
      base_branch: "ruby_3_4",
      gem_name: "rexml",
      current_version: "3.4.4",
      target_version: "3.4.5"
    )
    create(
      :pull_request,
      candidate_bump: bump,
      status: "merged",
      pr_number: 12_345,
      pr_url: "https://github.com/ruby/ruby/pull/12345"
    )

    get "/"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Merged security PRs")
    expect(response.body).to include("https://github.com/ruby/ruby/pull/12345")
    expect(response.body).to include("rexml 3.4.4")
    expect(response.body).to include("CVE-2026-0001")
  end
end
