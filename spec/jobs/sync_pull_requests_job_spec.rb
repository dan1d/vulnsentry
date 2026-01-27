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

    comments_fetcher = instance_double(Github::PullRequestCommentsFetcher)
    allow(Github::PullRequestCommentsFetcher).to receive(:new).and_return(comments_fetcher)
    allow(comments_fetcher).to receive(:fetch).and_return(
      issue_comments: [],
      reviews: [],
      review_comments: []
    )

    described_class.perform_now

    expect(pr.reload.status).to eq("closed")
    expect(pr.last_synced_at).to be_present
    expect(pr.comments_last_synced_at).to be_present
    expect(pr.comments_snapshot.fetch("issue_comments")).to eq([])
  end

  it "logs a warning with gh details when gh returns non-JSON" do
    cb = create(:candidate_bump)
    pr = create(:pull_request, candidate_bump: cb, pr_number: 15971, upstream_repo: "ruby/ruby", status: "open")

    status_fetcher = instance_double(Github::PullRequestStatusFetcher)
    allow(Github::PullRequestStatusFetcher).to receive(:new).and_return(status_fetcher)

    status = instance_double(Process::Status, exitstatus: 0)
    cmd_error =
      Github::GhCli::CommandError.new(
        "gh returned invalid JSON: unexpected end of input at line 1 column 1",
        cmd: %w[gh api /repos/ruby/ruby/pulls/15971],
        stdout: "",
        stderr: "",
        status: status
      )

    allow(status_fetcher).to receive(:fetch).and_raise(cmd_error)

    comments_fetcher = instance_double(Github::PullRequestCommentsFetcher)
    allow(Github::PullRequestCommentsFetcher).to receive(:new).and_return(comments_fetcher)
    allow(comments_fetcher).to receive(:fetch).and_return(issue_comments: [], reviews: [], review_comments: [])

    expect { described_class.perform_now(limit: 1) }.not_to raise_error

    ev = SystemEvent.where(kind: "sync_pull_requests").order(occurred_at: :desc).first
    expect(ev).to have_attributes(status: "warning")
    expect(ev.payload["pr_id"]).to eq(pr.id)
    expect(ev.payload["class"]).to eq("Github::GhCli::CommandError")
    expect(ev.payload["cmd"]).to be_present
    expect(ev.payload["exitstatus"]).to eq(0)
  end
end
