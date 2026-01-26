require "rails_helper"

RSpec.describe AdminQueries::CandidateBumpsQuery do
  it "filters by state and gem_name" do
    create(:candidate_bump, state: "ready_for_review", gem_name: "rexml")
    create(:candidate_bump, state: "approved", gem_name: "rake")

    rel = described_class.new.call({ state: "ready_for_review", gem_name: "rexml" })
    expect(rel.count).to eq(1)
    expect(rel.first.gem_name).to eq("rexml")
  end
end
