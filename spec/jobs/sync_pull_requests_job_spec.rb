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
    it "sets review_state to 'approved' when all reviewers approved" do
      cb = create(:candidate_bump)
      pr = create(:pull_request, candidate_bump: cb, pr_number: 123, upstream_repo: "ruby/ruby", status: "open")

      # Explicitly stub both fetchers with all required fields
      allow(status_fetcher).to receive(:fetch).and_return(
        status: "open",
        opened_at: "2026-01-25T10:00:00Z",
        merged_at: nil,
        closed_at: nil,
        body: "PR body",
        labels: []
      )
      allow(comments_fetcher).to receive(:fetch).and_return(
        issue_comments: [],
        reviews: [{ "id" => 1, "user" => "matz", "state" => "APPROVED", "body" => "LGTM" }],
        review_comments: []
      )

      described_class.perform_now

      # Debug: check for errors
      errors = SystemEvent.where(kind: "sync_pull_requests", status: "warning")
      expect(errors).to be_empty, "Sync errors: #{errors.map(&:message).join(', ')}"

      pr.reload
      expect(pr.last_synced_at).to be_present, "PR was not synced - last_synced_at is nil. PR count: #{PullRequest.count}"
      expect(pr.review_state).to eq("approved")
    end

    it "sets review_state to 'changes_requested' when any reviewer requests changes" do
      cb = create(:candidate_bump)
      pr = create(:pull_request, candidate_bump: cb, pr_number: 123, upstream_repo: "ruby/ruby", status: "open")

      stub_fetchers(reviews: [
        { "id" => 1, "user" => "matz", "state" => "APPROVED", "body" => "LGTM" },
        { "id" => 2, "user" => "ko1", "state" => "CHANGES_REQUESTED", "body" => "Fix this" }
      ])

      described_class.perform_now

      expect(pr.reload.review_state).to eq("changes_requested")
    end

    it "sets review_state to 'pending' when no reviews" do
      cb = create(:candidate_bump)
      pr = create(:pull_request, candidate_bump: cb, pr_number: 123, upstream_repo: "ruby/ruby", status: "open")

      stub_fetchers(reviews: [])

      described_class.perform_now

      expect(pr.reload.review_state).to eq("pending")
    end
  end

  describe "maintainer comment detection" do
    it "creates SystemEvent when maintainer comments" do
      cb = create(:candidate_bump)
      pr = create(:pull_request,
        candidate_bump: cb,
        pr_number: 123,
        upstream_repo: "ruby/ruby",
        status: "open",
        comments_snapshot: { "issue_comments" => [], "reviews" => [], "review_comments" => [] }
      )

      # New comment from maintainer
      allow(status_fetcher).to receive(:fetch).and_return(
        status: "closed",
        opened_at: "2026-01-25T10:00:00Z",
        merged_at: nil,
        closed_at: "2026-01-25T11:00:00Z",
        body: "PR body",
        labels: []
      )
      allow(comments_fetcher).to receive(:fetch).and_return(
        issue_comments: [{ "id" => 999, "user" => "kou", "body" => "Ruby 3.1 reached EOL", "created_at" => "2026-01-26T14:00:00Z" }],
        reviews: [],
        review_comments: []
      )

      described_class.perform_now

      event = SystemEvent.find_by(kind: "maintainer_feedback")
      expect(event).to be_present
      expect(event.message).to include("kou")
      expect(event.message).to include("PR #123")
      expect(event.payload["user"]).to eq("kou")
    end

    it "does not create SystemEvent for own comments" do
      cb = create(:candidate_bump)
      pr = create(:pull_request,
        candidate_bump: cb,
        pr_number: 123,
        upstream_repo: "ruby/ruby",
        status: "open",
        comments_snapshot: { "issue_comments" => [], "reviews" => [], "review_comments" => [] }
      )

      allow(status_fetcher).to receive(:fetch).and_return(
        status: "open",
        opened_at: "2026-01-25T10:00:00Z",
        merged_at: nil,
        closed_at: nil,
        body: "PR body",
        labels: []
      )
      allow(comments_fetcher).to receive(:fetch).and_return(
        issue_comments: [{ "id" => 999, "user" => "dan1d", "body" => "Bump submitted", "created_at" => "2026-01-26T14:00:00Z" }],
        reviews: [],
        review_comments: []
      )

      described_class.perform_now

      expect(SystemEvent.find_by(kind: "maintainer_feedback")).to be_nil
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
