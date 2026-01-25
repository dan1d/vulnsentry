require "rails_helper"

RSpec.describe Osv::Client do
  it "queries OSV for RubyGems vulnerabilities" do
    stub_request(:post, Osv::Client::URL)
      .with(body: hash_including(package: { name: "rexml", ecosystem: "RubyGems" }, version: "3.4.4"))
      .to_return(status: 200, body: { "vulns" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    data = described_class.new.query_rubygems(gem_name: "rexml", version: "3.4.4")
    expect(data).to eq({ "vulns" => [] })
  end
end
