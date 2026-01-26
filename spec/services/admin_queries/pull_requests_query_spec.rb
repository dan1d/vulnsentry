require "rails_helper"

RSpec.describe AdminQueries::PullRequestsQuery do
  it "filters by status and base_branch" do
    cb1 = create(:candidate_bump, base_branch: "master")
    cb2 = create(:candidate_bump, base_branch: "ruby_3_4")
    create(:pull_request, candidate_bump: cb1, status: "open")
    create(:pull_request, candidate_bump: cb2, status: "closed")

    rel = described_class.new.call({ status: "closed", base_branch: "ruby_3_4" })
    expect(rel.count).to eq(1)
    expect(rel.first.status).to eq("closed")
  end
end
