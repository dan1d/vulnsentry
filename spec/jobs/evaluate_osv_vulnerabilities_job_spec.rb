require "rails_helper"

RSpec.describe EvaluateOsvVulnerabilitiesJob, type: :job do
  it "creates advisories and candidate bumps for vulnerable bundled gems" do
    create(:branch_target, name: "master", enabled: true, maintenance_status: "normal")

    stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems")
      .to_return(status: 200, body: "rexml 3.4.4 https://github.com/ruby/rexml\n")

    stub_request(:get, "https://rubygems.org/api/v1/versions/rexml.json")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: [
          { "number" => "3.4.4" },
          { "number" => "3.4.5" },
          { "number" => "3.4.6" }
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
              "id" => "OSV-TEST-1",
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

    described_class.perform_now(limit_branches: 1)

    advisory = Advisory.find_by!(fingerprint: "osv:OSV-TEST-1")
    expect(advisory.gem_name).to eq("rexml")

    bump = CandidateBump.find_by!(advisory: advisory, base_branch: "master", gem_name: "rexml", target_version: "3.4.5")
    expect(bump.state).to eq("ready_for_review")
    expect(bump.proposed_diff).to include("-rexml 3.4.4")
    expect(bump.proposed_diff).to include("+rexml 3.4.5")
  end
end
