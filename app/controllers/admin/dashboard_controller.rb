class Admin::DashboardController < Admin::BaseController
  def index
    @open_prs = PullRequest.where(status: "open").order(created_at: :desc).limit(50)
    @recent_candidates = CandidateBump.order(created_at: :desc).limit(50)
    # Only count "supported" branches on the dashboard (enabled + non-EOL).
    # EOL branches remain in DB for auditability.
    @branch_targets = BranchTarget.where(enabled: true, maintenance_status: %w[normal security]).order(name: :asc)
    @config = BotConfig.instance
    @events = SystemEvent.order(occurred_at: :desc).limit(50)
  end
end
