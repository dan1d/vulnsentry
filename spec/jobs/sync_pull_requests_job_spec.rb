require "rails_helper"

RSpec.describe SyncPullRequestsJob, type: :job do
  let(:status_fetcher) { instance_double(Github::PullRequestStatusFetcher) }
  let(:comments_fetcher) { instance_double(Github::PullRequestCommentsFetcher) }

  before do
    allow(Github::PullRequestStatusFetcher).to receive(:new).and_return(status_fetcher)
    allow(Github::PullRequestCommentsFetcher).to receive(:new).and_return(comments_fetcher)
  end

  def stub_fetchers(status: "open", body: "PR body", labels: [], reviews: [])
    allow(status_fetcher).to receive(:fetch).and_return(
      status: status,
      opened_at: "2026-01-25T10:00:00Z",
      merged_at: nil,
      closed_at: status == "closed" ? "2026-01-25T11:00:00Z" : nil,
      body: body,
      labels: labels
    )
    allow(comments_fetcher).to receive(:fetch).and_return(
      issue_comments: [],
      reviews: reviews,
      review_comments: []
    )
  end

  it "updates PR status, body, and labels from GitHub data" do
    cb = create(:candidate_bump)
    pr = create(:pull_request, candidate_bump: cb, pr_number: 123, upstream_repo: "ruby/ruby", status: "open")

    stub_fetchers(status: "closed", body: "Security bump", labels: %w[Backport])

    described_class.perform_now

    pr.reload
    expect(pr.status).to eq("closed")
    expect(pr.body).to eq("Security bump")
    expect(pr.labels).to eq(%w[Backport])
    expect(pr.last_synced_at).to be_present
  end

  describe "scope filtering" do
    it "syncs only open PRs when scope is 'open'" do
      cb = create(:candidate_bump)
      open_pr = create(:pull_request, candidate_bump: cb, pr_number: 100, upstream_repo: "ruby/ruby", status: "open")

      cb2 = create(:candidate_bump)
      closed_pr = create(:pull_request, candidate_bump: cb2, pr_number: 101, upstream_repo: "ruby/ruby", status: "closed")

      stub_fetchers(status: "open")

      described_class.perform_now(scope: "open")

      expect(open_pr.reload.last_synced_at).to be_present
      expect(closed_pr.reload.last_synced_at).to be_nil
    end

    it "syncs only closed/merged PRs when scope is 'closed'" do
      cb = create(:candidate_bump)
      open_pr = create(:pull_request, candidate_bump: cb, pr_number: 100, upstream_repo: "ruby/ruby", status: "open")

      cb2 = create(:candidate_bump)
      closed_pr = create(:pull_request, candidate_bump: cb2, pr_number: 101, upstream_repo: "ruby/ruby", status: "closed")

      stub_fetchers(status: "closed")

      described_class.perform_now(scope: "closed")

      expect(open_pr.reload.last_synced_at).to be_nil
      expect(closed_pr.reload.last_synced_at).to be_present
    end
  end

  describe "review state derivation" do
    it "sets review_state based on reviews" do
      cb = create(:candidate_bump)
      pr = create(:pull_request, candidate_bump: cb, pr_number: 123, upstream_repo: "ruby/ruby", status: "open")

      stub_fetchers(reviews: [])

      described_class.perform_now

      pr.reload
      expect(pr.last_synced_at).to be_present
      expect(pr.review_state).to eq("pending")
    end
  end

  it "logs a warning with gh details when gh returns non-JSON" do
    cb = create(:candidate_bump)
    pr = create(:pull_request, candidate_bump: cb, pr_number: 15971, upstream_repo: "ruby/ruby", status: "open")

    status = instance_double(Process::Status, exitstatus: 0)
    cmd_error = Github::GhCli::CommandError.new(
      "gh returned invalid JSON: unexpected end of input at line 1 column 1",
      cmd: %w[gh api /repos/ruby/ruby/pulls/15971],
      stdout: "",
      stderr: "",
      status: status
    )

    allow(status_fetcher).to receive(:fetch).and_raise(cmd_error)

    expect { described_class.perform_now(limit: 1) }.not_to raise_error

    ev = SystemEvent.where(kind: "sync_pull_requests").order(occurred_at: :desc).first
    expect(ev).to have_attributes(status: "warning")
    expect(ev.payload["pr_id"]).to eq(pr.id)
    expect(ev.payload["class"]).to eq("Github::GhCli::CommandError")
    expect(ev.payload["cmd"]).to be_present
    expect(ev.payload["exitstatus"]).to eq(0)
  end
end
