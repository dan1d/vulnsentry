class Admin::CandidateBumpsController < Admin::BaseController
  def index
    per_page = (params[:per_page].presence || 20).to_i.clamp(10, 100)
    query = AdminQueries::CandidateBumpsQuery.new.call(params)
    @candidate_bumps = query.page(params[:page]).per(per_page)
  end

  def show
    @candidate_bump = CandidateBump.find(params[:id])
  end

  def update
    @candidate_bump = CandidateBump.find(params[:id])

    case params[:event]
    when "approve"
      @candidate_bump.update!(
        state: "approved",
        approved_at: Time.current,
        approved_by: current_admin_user.username
      )
      redirect_to admin_candidate_bump_path(@candidate_bump), notice: "Approved"
    when "reject"
      reason = params[:reason].presence || "rejected_by_admin"
      @candidate_bump.update!(state: "rejected", blocked_reason: reason)
      redirect_to admin_candidate_bump_path(@candidate_bump), notice: "Rejected"
    when "create_pr"
      enqueue_pr_creation!(@candidate_bump, draft: false)
      redirect_to admin_candidate_bump_path(@candidate_bump), notice: "PR creation enqueued"
    when "create_draft_pr"
      enqueue_pr_creation!(@candidate_bump, draft: true)
      redirect_to admin_candidate_bump_path(@candidate_bump), notice: "Draft PR creation enqueued"
    else
      head :bad_request
    end
  end

  private
    def enqueue_pr_creation!(candidate_bump, draft:)
      config = BotConfig.instance
      return if config.emergency_stop?
      return unless candidate_bump.state == "approved"

      CreatePullRequestJob.perform_later(candidate_bump.id, draft: draft)
    end
end
