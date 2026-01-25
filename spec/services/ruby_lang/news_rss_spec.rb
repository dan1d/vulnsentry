require "rails_helper"

RSpec.describe RubyLang::NewsRss do
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
end
