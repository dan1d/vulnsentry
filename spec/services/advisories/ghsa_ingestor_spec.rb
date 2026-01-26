require "rails_helper"

RSpec.describe Advisories::GhsaIngestor do
  it "creates advisory records for applicable GHSA vulnerabilities" do
    ghsa = instance_double(Ghsa::Client)
    allow(ghsa).to receive(:vulnerabilities_for_rubygem).and_return(
      [
        {
          "ghsaId" => "GHSA-xxxx-yyyy-zzzz",
          "cve" => "CVE-2026-0001",
          "advisoryUrl" => "https://github.com/advisories/GHSA-xxxx-yyyy-zzzz",
          "vulnerableVersionRange" => "< 3.4.5",
          "firstPatchedVersion" => "3.4.5"
        }
      ]
    )

    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).and_return(nil)

    ingestor = described_class.new(ghsa: ghsa, ruby_lang_rss: rss)
    advisories = ingestor.ingest_for_version(gem_name: "rexml", version: "3.4.4")

    expect(advisories.length).to eq(1)
    adv = advisories.first
    expect(adv.source).to eq("ghsa")
    expect(adv.fingerprint).to eq("ghsa:GHSA-xxxx-yyyy-zzzz")
    expect(adv.cve).to eq("CVE-2026-0001")
  end

  it "supports comma-separated version range constraints" do
    ghsa = instance_double(Ghsa::Client)
    allow(ghsa).to receive(:vulnerabilities_for_rubygem).and_return(
      [
        {
          "ghsaId" => "GHSA-comma-range",
          "cve" => "CVE-2026-0002",
          "advisoryUrl" => "https://github.com/advisories/GHSA-comma-range",
          "vulnerableVersionRange" => ">= 3.3.3, <= 3.4.1",
          "firstPatchedVersion" => "3.4.2"
        }
      ]
    )

    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).and_return(nil)

    ingestor = described_class.new(ghsa: ghsa, ruby_lang_rss: rss)
    advisories = ingestor.ingest_for_version(gem_name: "rexml", version: "3.4.0")

    expect(advisories.length).to eq(1)
    expect(advisories.first.fingerprint).to eq("ghsa:GHSA-comma-range")
  end

  it "logs warning and continues when a GHSA range cannot be parsed" do
    ghsa = instance_double(Ghsa::Client)
    allow(ghsa).to receive(:vulnerabilities_for_rubygem).and_return(
      [
        {
          "ghsaId" => "GHSA-bad-range",
          "cve" => "CVE-2026-0003",
          "advisoryUrl" => "https://github.com/advisories/GHSA-bad-range",
          "vulnerableVersionRange" => ">= 3.3.3, <= 3.4.1, ???",
          "firstPatchedVersion" => "3.4.2"
        },
        {
          "ghsaId" => "GHSA-good",
          "cve" => "CVE-2026-0004",
          "advisoryUrl" => "https://github.com/advisories/GHSA-good",
          "vulnerableVersionRange" => "< 9.9.9",
          "firstPatchedVersion" => "9.9.9"
        }
      ]
    )

    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).and_return(nil)

    ingestor = described_class.new(ghsa: ghsa, ruby_lang_rss: rss)

    expect { ingestor.ingest_for_version(gem_name: "rexml", version: "3.4.0") }
      .to change { SystemEvent.where(kind: "ghsa_ingest", status: "warning").count }.by(1)

    expect(Advisory.find_by(fingerprint: "ghsa:GHSA-good")).to be_present
  end
end
