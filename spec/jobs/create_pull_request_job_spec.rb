require "rails_helper"

RSpec.describe CreatePullRequestJob, type: :job do
  it "creates PullRequest and updates candidate to submitted" do
    BotConfig.delete_all
    create(:bot_config, emergency_stop: false)

    branch = create(:branch_target, name: "master", enabled: true, maintenance_status: "normal")
    advisory = create(:advisory, source: "osv", fingerprint: "osv:OSV-PR-1", gem_name: "rexml")
    candidate = create(
      :candidate_bump,
      advisory: advisory,
      branch_target: branch,
      base_branch: "master",
      gem_name: "rexml",
      current_version: "3.4.4",
      target_version: "3.4.5",
      state: "approved"
    )

    creator = instance_double(Github::RubyCorePrCreator)
    allow(Github::RubyCorePrCreator).to receive(:new).and_return(creator)
    allow(creator).to receive(:create_for_candidate!).and_return({ number: 12_345, url: "https://github.com/ruby/ruby/pull/12345" })

    described_class.perform_now(candidate.id, draft: false)

    pr = PullRequest.find_by!(candidate_bump: candidate)
    expect(pr.pr_number).to eq(12_345)
    expect(candidate.reload.state).to eq("submitted")
  end

  it "persists exception backtrace in SystemEvent when PR creation fails" do
    BotConfig.delete_all
    create(:bot_config, emergency_stop: false)

    branch = create(:branch_target, name: "master", enabled: true, maintenance_status: "normal")
    advisory = create(:advisory, source: "osv", fingerprint: "osv:OSV-PR-2", gem_name: "rexml")
    candidate = create(
      :candidate_bump,
      advisory: advisory,
      branch_target: branch,
      base_branch: "master",
      gem_name: "rexml",
      current_version: "3.4.4",
      target_version: "3.4.5",
      state: "approved"
    )

    creator = instance_double(Github::RubyCorePrCreator)
    allow(Github::RubyCorePrCreator).to receive(:new).and_return(creator)
    allow(creator).to receive(:create_for_candidate!).and_raise(TypeError, "no implicit conversion of nil into String")

    expect { described_class.perform_now(candidate.id, draft: false) }.to raise_error(TypeError)

    ev = SystemEvent.order(occurred_at: :desc).first
    expect(ev).to have_attributes(kind: "create_pr", status: "failed")
    expect(ev.payload.dig("exception", "class")).to eq("TypeError")
    expect(ev.payload.dig("exception", "backtrace")).to be_present
  end

  it "does nothing when emergency_stop is enabled" do
    BotConfig.delete_all
    create(:bot_config, emergency_stop: true)

    candidate = create(:candidate_bump, state: "approved")
    described_class.perform_now(candidate.id)

    expect(candidate.reload.state).to eq("approved")
    expect(PullRequest.where(candidate_bump: candidate)).to be_empty
  end
end
