# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectFiles::Fetcher do
  let(:project) { build(:project, slug: "ruby", upstream_repo: "ruby/ruby", file_path: "gems/bundled_gems") }
  let(:fetcher) { described_class.new(project) }

  describe "#fetch" do
    let(:file_content) { "rexml 3.4.4 https://github.com/ruby/rexml\n" }

    before do
      stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems")
        .to_return(status: 200, body: file_content)
    end

    it "fetches file content from GitHub" do
      result = fetcher.fetch(branch: "master")
      expect(result).to eq(file_content)
    end

    it "caches the result" do
      fetcher.fetch(branch: "master")
      fetcher.fetch(branch: "master")

      expect(WebMock).to have_requested(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems").once
    end

    it "uses provided repo over project's repo" do
      stub_request(:get, "https://raw.githubusercontent.com/other/repo/main/gems/bundled_gems")
        .to_return(status: 200, body: file_content)

      result = fetcher.fetch(repo: "other/repo", branch: "main")
      expect(result).to eq(file_content)
    end
  end

  describe "#fetch!" do
    let(:file_content) { "rexml 3.4.4 https://github.com/ruby/rexml\n" }

    it "fetches without caching" do
      stub = stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems")
             .to_return(status: 200, body: file_content)

      fetcher.fetch!(branch: "master")
      fetcher.fetch!(branch: "master")

      expect(stub).to have_been_requested.twice
    end
  end

  describe "error handling" do
    it "raises FetchError for 404 responses" do
      stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/nonexistent/gems/bundled_gems")
        .to_return(status: 404, body: "Not Found")

      expect { fetcher.fetch!(branch: "nonexistent") }
        .to raise_error(ProjectFiles::Fetcher::FetchError, /not found/i)
    end

    it "raises FetchError for network errors" do
      stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems")
        .to_raise(SocketError.new("Connection refused"))

      expect { fetcher.fetch!(branch: "master") }
        .to raise_error(ProjectFiles::Fetcher::FetchError, /network error/i)
    end

    it "follows redirects" do
      stub_request(:get, "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems")
        .to_return(status: 302, headers: { "Location" => "https://example.com/redirect" })

      stub_request(:get, "https://example.com/redirect")
        .to_return(status: 200, body: "redirected content")

      result = fetcher.fetch!(branch: "master")
      expect(result).to eq("redirected content")
    end
  end
end
