require "rails_helper"

RSpec.describe RubyLang::SecurityAdvisoryResolver do
  it "fails closed (fallback) on ruby-lang timeout and records event" do
    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).and_return("https://www.ruby-lang.org/en/news/x")

    stub_request(:get, "https://www.ruby-lang.org/en/news/x").to_timeout

    resolver = described_class.new(rss: rss)
    fixed = resolver.resolve_fixed_version(
      gem_name: "rexml",
      current_version: "3.3.8",
      cve: "CVE-2024-49761",
      fallback_fixed_version: "3.4.5"
    )

    expect(fixed).to eq("3.4.5")
    expect(SystemEvent.where(kind: "ruby_lang_resolver").count).to eq(1)
  end
end
