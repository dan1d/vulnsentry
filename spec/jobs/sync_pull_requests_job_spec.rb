require "rails_helper"

RSpec.describe SyncPullRequestsJob, type: :job do
  it "updates PR status from GitHub data" do
    cb = create(:candidate_bump)
    pr = create(:pull_request, candidate_bump: cb, pr_number: 123, upstream_repo: "ruby/ruby", status: "open")

    fetcher = instance_double(Github::PullRequestStatusFetcher)
    allow(Github::PullRequestStatusFetcher).to receive(:new).and_return(fetcher)
    allow(fetcher).to receive(:fetch).and_return(
      status: "closed",
      opened_at: "2026-01-25T10:00:00Z",
      merged_at: nil,
      closed_at: "2026-01-25T11:00:00Z"
    )

    described_class.perform_now

    expect(pr.reload.status).to eq("closed")
    expect(pr.last_synced_at).to be_present
  end
end
