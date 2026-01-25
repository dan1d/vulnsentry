require "rails_helper"

RSpec.describe RubyCore::BundledGemsFetcher do
  it "fetches bundled_gems for a branch from raw github" do
    url = "https://raw.githubusercontent.com/ruby/ruby/master/gems/bundled_gems"
    stub_request(:get, url).to_return(status: 200, body: "rexml 3.4.4 https://github.com/ruby/rexml\n")

    content = described_class.new.fetch(repo: "ruby/ruby", branch: "master")
    expect(content).to include("rexml 3.4.4")
  end
end
