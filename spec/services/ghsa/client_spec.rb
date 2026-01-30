require "rails_helper"

RSpec.describe Ghsa::Client do
  # Caching is disabled globally in rails_helper.rb

  it "parses vulnerabilities from gh graphql response" do
    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:json!).and_return(
      "data" => {
        "securityVulnerabilities" => {
          "nodes" => [
            {
              "vulnerableVersionRange" => "< 3.4.5",
              "firstPatchedVersion" => { "identifier" => "3.4.5" },
              "advisory" => {
                "ghsaId" => "GHSA-xxxx-yyyy-zzzz",
                "permalink" => "https://github.com/advisories/GHSA-xxxx-yyyy-zzzz",
                "identifiers" => [
                  { "type" => "CVE", "value" => "CVE-2026-0001" }
                ],
                "publishedAt" => "2026-01-01T00:00:00Z",
                "updatedAt" => "2026-01-15T00:00:00Z"
              },
              "package" => { "name" => "rexml", "ecosystem" => "RUBYGEMS" }
            }
          ]
        }
      }
    )

    client = described_class.new(gh: gh)
    vulns = client.vulnerabilities_for_rubygem(gem_name: "rexml")
    expect(vulns.length).to eq(1)
    expect(vulns.first["ghsaId"]).to eq("GHSA-xxxx-yyyy-zzzz")
    expect(vulns.first["cve"]).to eq("CVE-2026-0001")
    expect(vulns.first["firstPatchedVersion"]).to eq("3.4.5")
    expect(vulns.first["publishedAt"]).to eq("2026-01-01T00:00:00Z")
    expect(vulns.first["updatedAt"]).to eq("2026-01-15T00:00:00Z")
  end
end
