require "rails_helper"

RSpec.describe RubyLang::SecurityAdvisoryResolver do
  around do |example|
    old = ENV["ENABLE_DEEPSEEK_RUBYLANG_FALLBACK"]
    ENV["ENABLE_DEEPSEEK_RUBYLANG_FALLBACK"] = "true"
    example.run
  ensure
    ENV["ENABLE_DEEPSEEK_RUBYLANG_FALLBACK"] = old
  end

  it "uses DeepSeek when deterministic parse fails and AI is enabled" do
    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).and_return("https://www.ruby-lang.org/en/news/x")

    stub_request(:get, "https://www.ruby-lang.org/en/news/x").to_return(status: 200, body: "<p>No version</p>")

    ai = instance_double(Ai::DeepseekClient, enabled?: true)
    allow(ai).to receive(:extract_json!).and_return({ "gem" => "rexml", "fixed_version" => "3.3.9" })

    resolver = described_class.new(rss: rss, ai_client: ai)
    fixed = resolver.resolve_fixed_version(
      gem_name: "rexml",
      current_version: "3.3.8",
      cve: "CVE-2024-49761",
      fallback_fixed_version: "3.4.5"
    )

    expect(fixed).to eq("3.3.9")
  end

  it "rejects AI output for wrong gem and falls back" do
    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).and_return("https://www.ruby-lang.org/en/news/x")

    stub_request(:get, "https://www.ruby-lang.org/en/news/x").to_return(status: 200, body: "<p>No version</p>")

    ai = instance_double(Ai::DeepseekClient, enabled?: true)
    allow(ai).to receive(:extract_json!).and_return({ "gem" => "other", "fixed_version" => "9.9.9" })

    resolver = described_class.new(rss: rss, ai_client: ai)
    fixed = resolver.resolve_fixed_version(
      gem_name: "rexml",
      current_version: "3.3.8",
      cve: "CVE-2024-49761",
      fallback_fixed_version: "3.4.5"
    )

    expect(fixed).to eq("3.4.5")
  end

  it "falls back when DeepSeek returns invalid JSON/error" do
    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).and_return("https://www.ruby-lang.org/en/news/x")

    stub_request(:get, "https://www.ruby-lang.org/en/news/x")
      .to_return(status: 200, body: "<p>No version</p>")

    ai = instance_double(Ai::DeepseekClient, enabled?: true)
    allow(ai).to receive(:extract_json!).and_raise(Ai::DeepseekClient::Error, "bad json")

    resolver = described_class.new(rss: rss, ai_client: ai)
    fixed = resolver.resolve_fixed_version(
      gem_name: "rexml",
      current_version: "3.3.8",
      cve: "CVE-2024-49761",
      fallback_fixed_version: "3.4.5"
    )

    expect(fixed).to eq("3.4.5")
  end

  it "falls back when DeepSeek suggests a non-newer version" do
    rss = instance_double(RubyLang::NewsRss)
    allow(rss).to receive(:find_announcement_url_by_cve).and_return("https://www.ruby-lang.org/en/news/x")

    stub_request(:get, "https://www.ruby-lang.org/en/news/x")
      .to_return(status: 200, body: "<p>No version</p>")

    ai = instance_double(Ai::DeepseekClient, enabled?: true)
    allow(ai).to receive(:extract_json!).and_return({ "gem" => "rexml", "fixed_version" => "3.3.8" })

    resolver = described_class.new(rss: rss, ai_client: ai)
    fixed = resolver.resolve_fixed_version(
      gem_name: "rexml",
      current_version: "3.3.8",
      cve: "CVE-2024-49761",
      fallback_fixed_version: "3.4.5"
    )

    expect(fixed).to eq("3.4.5")
  end
end
