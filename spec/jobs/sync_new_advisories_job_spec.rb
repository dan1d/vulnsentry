require "rails_helper"

RSpec.describe SyncNewAdvisoriesJob, type: :job do
  # Caching is disabled globally in rails_helper.rb

  it "syncs new advisories for bundled gems" do
    create(:branch_target, name: "master", enabled: true, maintenance_status: "normal")

    stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems")
      .to_return(status: 200, body: "rexml 3.4.4 https://github.com/ruby/rexml\n")

    stub_request(:get, "https://rubygems.org/api/v1/versions/rexml.json")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: [
          { "number" => "3.4.4" },
          { "number" => "3.4.5" }
        ].to_json
      )

    stub_request(:get, RubyLang::NewsRss::URL)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/rss+xml" },
        body: <<~XML
          <?xml version="1.0"?>
          <rss version="2.0"><channel><title>Ruby</title></channel></rss>
        XML
      )

    allow_any_instance_of(RubyLang::NewsRss).to receive(:find_announcement_url_by_cve).and_return(nil)

    gh = instance_double(Github::GhCli)
    allow(Github::GhCli).to receive(:new).and_return(gh)
    allow(gh).to receive(:json!).and_return(
      "data" => {
        "securityVulnerabilities" => {
          "nodes" => []
        }
      }
    )

    stub_request(:post, Osv::Client::URL)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "vulns" => [
            {
              "id" => "OSV-SYNC-1",
              "aliases" => [ "CVE-2026-0001" ],
              "published" => "2026-01-01T00:00:00Z",
              "references" => [ { "type" => "ADVISORY", "url" => "https://example.test/advisory" } ],
              "affected" => [
                { "ranges" => [ { "events" => [ { "introduced" => "0" }, { "fixed" => "3.4.5" } ] } ] }
              ]
            }
          ]
        }.to_json
      )

    described_class.perform_now

    advisory = Advisory.find_by!(fingerprint: "osv:OSV-SYNC-1")
    expect(advisory.gem_name).to eq("rexml")

    event = SystemEvent.find_by!(kind: "sync_new_advisories")
    expect(event.status).to eq("ok")
    expect(event.payload["total_new_advisories"]).to eq(1)
    expect(event.payload["by_project"]).to be_present
  end

  it "skips gems that have been recently checked" do
    branch = create(:branch_target, name: "master", enabled: true, maintenance_status: "normal")

    # Create an existing advisory that was updated recently
    advisory = create(:advisory, gem_name: "rexml", fingerprint: "osv:EXISTING-1", updated_at: 1.hour.ago)
    bundle = create(:patch_bundle,
      branch_target: branch,
      gem_name: "rexml",
      current_version: "3.4.4",
      base_branch: "master",
      state: "ready_for_review")
    create(:bundled_advisory, patch_bundle: bundle, advisory: advisory)

    stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems")
      .to_return(status: 200, body: "rexml 3.4.4 https://github.com/ruby/rexml\n")

    # The job should not make any OSV/GHSA API calls since rexml was recently checked
    described_class.perform_now

    event = SystemEvent.find_by!(kind: "sync_new_advisories")
    expect(event.payload["total_gems_checked"]).to eq(0)
  end

  it "handles fetch errors gracefully" do
    create(:branch_target, name: "master", enabled: true, maintenance_status: "normal")

    stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems")
      .to_return(status: 404)

    expect { described_class.perform_now }.not_to raise_error

    event = SystemEvent.find_by!(kind: "bundled_gems_fetch")
    expect(event.status).to eq("failed")
  end
end
