require "rails_helper"

RSpec.describe RubyLang::SecurityAdvisoryResolver do
  let(:rss) { instance_double(RubyLang::NewsRss) }

  it "prefers ruby-lang parsed fixed version when available" do
    allow(rss).to receive(:find_announcement_url_by_cve).and_return("https://www.ruby-lang.org/en/news/x")
    stub_request(:get, "https://www.ruby-lang.org/en/news/x").to_return(
      status: 200,
      body: "<p>Please update REXML gem to version 3.3.9 or later.</p>"
    )

    resolver = described_class.new(rss: rss)
    fixed = resolver.resolve_fixed_version(
      gem_name: "rexml",
      current_version: "3.3.8",
      cve: "CVE-2024-49761",
      fallback_fixed_version: "3.3.8"
    )

    expect(fixed).to eq("3.3.9")
  end

  it "falls back when ruby-lang fetch fails" do
    allow(rss).to receive(:find_announcement_url_by_cve).and_return("https://www.ruby-lang.org/en/news/x")
    stub_request(:get, "https://www.ruby-lang.org/en/news/x").to_return(status: 500, body: "nope")

    resolver = described_class.new(rss: rss)
    fixed = resolver.resolve_fixed_version(
      gem_name: "rexml",
      current_version: "3.3.8",
      cve: "CVE-2024-49761",
      fallback_fixed_version: "3.4.5"
    )

    expect(fixed).to eq("3.4.5")
  end
end
