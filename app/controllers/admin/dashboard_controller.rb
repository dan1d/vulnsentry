class Admin::DashboardController < Admin::BaseController
  def index
    @open_prs = PullRequest.where(status: "open").order(created_at: :desc).limit(50)
    @recent_candidates = CandidateBump.order(created_at: :desc).limit(50)
    @branch_targets = BranchTarget.order(name: :asc)
    @config = BotConfig.instance
  end
end
