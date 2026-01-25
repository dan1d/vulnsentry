require "rails_helper"

RSpec.describe RefreshBranchTargetsJob, type: :job do
  it "creates/updates branch targets for supported branches and ensures master" do
    fake_fetcher = instance_double(RubyLang::MaintenanceBranches)
    allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(fake_fetcher)
    allow(fake_fetcher).to receive(:fetch_supported).and_return([
      RubyLang::MaintenanceBranches::Branch.new("3.4", "normal"),
      RubyLang::MaintenanceBranches::Branch.new("3.2", "security")
    ])

    described_class.perform_now

    expect(BranchTarget.find_by!(name: "ruby_3_4").maintenance_status).to eq("normal")
    expect(BranchTarget.find_by!(name: "ruby_3_2").maintenance_status).to eq("security")
    expect(BranchTarget.find_by!(name: "master")).to be_present
  end
end

