require "rails_helper"

RSpec.describe Advisories::OsvIngestor do
  it "prefers ruby-lang URL when CVE announcement exists" do
    osv = instance_double(Osv::Client)
    allow(osv).to receive(:query_rubygems).and_return(
      "vulns" => [
        {
          "id" => "OSV-TEST-1",
          "aliases" => [ "CVE-2024-49761" ],
          "references" => [ { "type" => "ADVISORY", "url" => "https://osv.test/advisory" } ]
        }
      ]
    )

    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).with("CVE-2024-49761").and_return("https://ruby-lang.test/cve")

    ingestor = described_class.new(osv: osv, ruby_lang_rss: rss)
    advisories = ingestor.ingest_for_version(gem_name: "rexml", version: "3.4.4")

    expect(advisories.length).to eq(1)
    adv = advisories.first
    expect(adv.source).to eq("osv")
    expect(adv.cve).to eq("CVE-2024-49761")
    expect(adv.advisory_url).to eq("https://ruby-lang.test/cve")
    expect(adv.raw["ruby_lang_url"]).to eq("https://ruby-lang.test/cve")
  end
end
