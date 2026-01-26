require "rails_helper"

RSpec.describe AdminQueries::AdvisoriesQuery do
  it "filters by source and q" do
    create(:advisory, source: "osv", fingerprint: "osv:OSV-1", gem_name: "rexml")
    create(:advisory, source: "ghsa", fingerprint: "ghsa:GHSA-1", gem_name: "rake")

    rel = described_class.new.call({ source: "osv", q: "rexml" })
    expect(rel.count).to eq(1)
    expect(rel.first.fingerprint).to eq("osv:OSV-1")
  end
end
