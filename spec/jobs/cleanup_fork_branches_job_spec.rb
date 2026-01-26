require "rails_helper"

RSpec.describe CleanupForkBranchesJob, type: :job do
  it "deletes fork branches for merged PRs and marks them deleted" do
    BotConfig.delete_all
    create(:bot_config, emergency_stop: false)

    cb = create(:candidate_bump)
    pr = create(:pull_request, candidate_bump: cb, status: "merged", head_branch: "bump-rexml-3.4.5-master")

    cleaner = instance_double(Github::ForkBranchCleaner)
    allow(Github::ForkBranchCleaner).to receive(:new).and_return(cleaner)
    allow(cleaner).to receive(:delete_branch).and_return(true)

    described_class.perform_now(limit: 10)

    expect(pr.reload.branch_deleted_at).to be_present
  end

  it "does not delete non-bump branches" do
    BotConfig.delete_all
    create(:bot_config, emergency_stop: false)

    cb = create(:candidate_bump)
    pr = create(:pull_request, candidate_bump: cb, status: "merged", head_branch: "master")

    cleaner = instance_double(Github::ForkBranchCleaner)
    allow(Github::ForkBranchCleaner).to receive(:new).and_return(cleaner)
    allow(cleaner).to receive(:delete_branch)

    described_class.perform_now(limit: 10)

    expect(pr.reload.branch_deleted_at).to be_nil
    expect(cleaner).not_to have_received(:delete_branch)
  end
end
