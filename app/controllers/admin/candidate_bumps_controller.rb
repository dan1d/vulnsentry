class Admin::CandidateBumpsController < Admin::BaseController
  def index
    @candidate_bumps = CandidateBump.order(created_at: :desc).limit(200)
  end

  def show
    @candidate_bump = CandidateBump.find(params[:id])
  end

  def update
    @candidate_bump = CandidateBump.find(params[:id])

    case params[:event]
    when "approve"
      @candidate_bump.update!(state: "approved", approved_at: Time.current, approved_by: current_admin_user)
      redirect_to admin_candidate_bump_path(@candidate_bump), notice: "Approved"
    when "reject"
      reason = params[:reason].presence || "rejected_by_admin"
      @candidate_bump.update!(state: "rejected", blocked_reason: reason)
      redirect_to admin_candidate_bump_path(@candidate_bump), notice: "Rejected"
    else
      head :bad_request
    end
  end

  private
    def current_admin_user
      ENV.fetch("ADMIN_USER", "admin")
    end
end
