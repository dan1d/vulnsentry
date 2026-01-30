require "rails_helper"

RSpec.describe RubyLang::NewsRss do
  # Caching is disabled globally in rails_helper.rb

  it "finds announcement URL by CVE from RSS feed" do
    rss = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Ruby News</title>
          <item>
            <title>CVE-2024-49761: ReDoS vulnerability in REXML</title>
            <link>https://www.ruby-lang.org/en/news/2024/10/28/redos-rexml-cve-2024-49761/</link>
            <description>There is a vulnerability CVE-2024-49761</description>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, RubyLang::NewsRss::URL).to_return(status: 200, body: rss)

    url = described_class.new.find_announcement_url_by_cve("CVE-2024-49761")
    expect(url).to eq("https://www.ruby-lang.org/en/news/2024/10/28/redos-rexml-cve-2024-49761/")
  end

  it "returns nil on fetch error" do
    stub_request(:get, RubyLang::NewsRss::URL).to_return(status: 500, body: "nope")
    url = described_class.new.find_announcement_url_by_cve("CVE-2024-49761")
    expect(url).to be_nil
  end

  context "with caching enabled" do
    before do
      described_class.enable_cache!
      # Use memory store for caching tests (test env uses null_store by default)
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    after do
      Rails.cache = @original_cache
    end

    it "caches the RSS feed" do
      rss = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Ruby</title></channel></rss>
      XML

      stub = stub_request(:get, RubyLang::NewsRss::URL).to_return(status: 200, body: rss)

      client = described_class.new
      client.find_announcement_url_by_cve("CVE-2024-1111")
      client.find_announcement_url_by_cve("CVE-2024-2222")

      expect(stub).to have_been_requested.once
    end
  end
end
