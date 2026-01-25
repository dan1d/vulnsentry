require "rails_helper"

RSpec.describe Evaluation::CandidateBumpBuilder do
  it "creates a ready_for_review candidate bump when fix is resolvable" do
    branch = create(:branch_target, name: "master", enabled: true, maintenance_status: "normal")

    advisory = Advisory.create!(
      fingerprint: "osv:OSV-TEST-1",
      gem_name: "rexml",
      source: "osv",
      cve: "CVE-2026-0001",
      advisory_url: "https://example.test/advisory",
      raw: {
        "affected" => [
          { "ranges" => [ { "events" => [ { "introduced" => "0" }, { "fixed" => "3.4.5" } ] } ] }
        ]
      }
    )

    entry = RubyCore::BundledGemsFile::Entry.new(
      "rexml",
      "3.4.4",
      "https://github.com/ruby/rexml",
      nil,
      1,
      "rexml 3.4.4 https://github.com/ruby/rexml\n"
    )

    stub_request(:get, "https://rubygems.org/api/v1/versions/rexml.json")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: [ { "number" => "3.4.4" }, { "number" => "3.4.5" } ].to_json
      )

    allow_any_instance_of(RubyLang::SecurityAdvisoryResolver).to receive(:resolve_fixed_version).and_return("3.4.5")

    builder = described_class.new
    builder.build!(
      branch_target: branch,
      bundled_gems_content: "rexml 3.4.4 https://github.com/ruby/rexml\n",
      entry: entry,
      advisory: advisory
    )

    bump = CandidateBump.find_by!(advisory: advisory, branch_target: branch)
    expect(bump.state).to eq("ready_for_review")
    expect(bump.proposed_diff).to include("+rexml 3.4.5")
  end
end

