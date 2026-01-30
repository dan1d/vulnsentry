require "rails_helper"

RSpec.describe RubyCore::BundledGemsFetcher do
  # Caching is disabled globally in rails_helper.rb

  it "fetches bundled_gems for a branch from raw github" do
    url = "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems"
    stub_request(:get, url).to_return(status: 200, body: "rexml 3.4.4 https://github.com/ruby/rexml\n")

    content = described_class.new.fetch(repo: "ruby/ruby", branch: "master")
    expect(content).to include("rexml 3.4.4")
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

    it "caches responses for the same branch" do
      url = "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems"
      stub = stub_request(:get, url).to_return(status: 200, body: "rexml 3.4.4\n")

      fetcher = described_class.new
      fetcher.fetch(repo: "ruby/ruby", branch: "master")
      fetcher.fetch(repo: "ruby/ruby", branch: "master")

      expect(stub).to have_been_requested.once
    end

    it "can invalidate cache for a branch" do
      url = "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems"
      stub = stub_request(:get, url).to_return(status: 200, body: "rexml 3.4.4\n")

      fetcher = described_class.new
      fetcher.fetch(repo: "ruby/ruby", branch: "master")
      fetcher.invalidate(repo: "ruby/ruby", branch: "master")
      fetcher.fetch(repo: "ruby/ruby", branch: "master")

      expect(stub).to have_been_requested.twice
    end
  end
end
