require "rails_helper"

RSpec.describe RefreshBranchTargetsJob, type: :job do
  before do
    allow_any_instance_of(Ai::MaintenanceBranchesCrossCheck).to receive(:enabled?).and_return(false)
  end

  it "creates/updates branch targets for supported branches and ensures master" do
    fake_fetcher = instance_double(RubyLang::MaintenanceBranches)
    allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(fake_fetcher)
    allow(fake_fetcher).to receive(:fetch_html).and_return("<html/>")
    allow(fake_fetcher).to receive(:parse_all_html).and_return([
      RubyLang::MaintenanceBranches::Branch.new("3.4", "normal"),
      RubyLang::MaintenanceBranches::Branch.new("3.2", "security"),
      RubyLang::MaintenanceBranches::Branch.new("3.1", "eol")
    ])

    described_class.perform_now

    expect(BranchTarget.find_by!(name: "ruby_3_4").maintenance_status).to eq("normal")
    expect(BranchTarget.find_by!(name: "ruby_3_2").maintenance_status).to eq("security")
    expect(BranchTarget.find_by!(name: "ruby_3_1")).to have_attributes(maintenance_status: "eol", enabled: false)
    expect(BranchTarget.find_by!(name: "master")).to be_present
  end

  it "marks branches no longer on ruby-lang.org as EOL" do
    # Simulate an old branch that was once supported but is now gone from the page
    old_branch = BranchTarget.create!(
      name: "ruby_3_0",
      maintenance_status: "security",
      enabled: true,
      source_url: "https://www.ruby-lang.org/en/downloads/branches/"
    )

    fake_fetcher = instance_double(RubyLang::MaintenanceBranches)
    allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(fake_fetcher)
    allow(fake_fetcher).to receive(:fetch_html).and_return("<html/>")
    # 3.0 is no longer on the page at all
    allow(fake_fetcher).to receive(:parse_all_html).and_return([
      RubyLang::MaintenanceBranches::Branch.new("3.4", "normal"),
      RubyLang::MaintenanceBranches::Branch.new("3.3", "normal")
    ])

    described_class.perform_now

    old_branch.reload
    expect(old_branch.maintenance_status).to eq("eol")
    expect(old_branch.enabled).to be false
  end

  it "does not mark master as EOL even if not on page" do
    BranchTarget.create!(name: "master", maintenance_status: "normal", enabled: true)

    fake_fetcher = instance_double(RubyLang::MaintenanceBranches)
    allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(fake_fetcher)
    allow(fake_fetcher).to receive(:fetch_html).and_return("<html/>")
    allow(fake_fetcher).to receive(:parse_all_html).and_return([
      RubyLang::MaintenanceBranches::Branch.new("3.4", "normal")
    ])

    described_class.perform_now

    master = BranchTarget.find_by!(name: "master")
    expect(master.maintenance_status).to eq("normal")
    expect(master.enabled).to be true
  end
end
