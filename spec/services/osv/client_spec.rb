require "rails_helper"

RSpec.describe Osv::Client do
  # Caching is disabled globally in rails_helper.rb

  it "queries OSV for RubyGems vulnerabilities" do
    stub_request(:post, Osv::Client::URL)
      .with(body: hash_including(package: { name: "rexml", ecosystem: "RubyGems" }, version: "3.4.4"))
      .to_return(status: 200, body: { "vulns" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    data = described_class.new.query_rubygems(gem_name: "rexml", version: "3.4.4")
    expect(data).to eq({ "vulns" => [] })
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

    it "caches responses for subsequent calls" do
      stub = stub_request(:post, Osv::Client::URL)
        .with(body: hash_including(package: { name: "rake", ecosystem: "RubyGems" }, version: "13.0.0"))
        .to_return(status: 200, body: { "vulns" => [] }.to_json, headers: { "Content-Type" => "application/json" })

      client = described_class.new

      # First call hits the API
      client.query_rubygems(gem_name: "rake", version: "13.0.0")
      # Second call should use cache
      client.query_rubygems(gem_name: "rake", version: "13.0.0")

      expect(stub).to have_been_requested.once
    end

    it "bypasses cache with force_refresh" do
      stub = stub_request(:post, Osv::Client::URL)
        .with(body: hash_including(package: { name: "rake", ecosystem: "RubyGems" }, version: "13.0.0"))
        .to_return(status: 200, body: { "vulns" => [] }.to_json, headers: { "Content-Type" => "application/json" })

      client = described_class.new

      # First call
      client.query_rubygems(gem_name: "rake", version: "13.0.0")
      # Force refresh bypasses cache
      client.query_rubygems(gem_name: "rake", version: "13.0.0", force_refresh: true)

      expect(stub).to have_been_requested.twice
    end
  end
end
