require "rails_helper"

RSpec.describe AdminQueries::BranchTargetsQuery do
  it "filters by enabled and maintenance_status" do
    create(:branch_target, enabled: true, maintenance_status: "normal")
    create(:branch_target, enabled: false, maintenance_status: "security")

    rel = described_class.new.call({ enabled: "false", maintenance_status: "security" })
    expect(rel.count).to eq(1)
    expect(rel.first.enabled).to be(false)
  end
end
