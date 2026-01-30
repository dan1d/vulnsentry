class Admin::DashboardController < Admin::BaseController
  def index
    @open_prs = PullRequest.where(status: "open").order(created_at: :desc).limit(50)
    @recent_candidates = CandidateBump.order(created_at: :desc).limit(50)
    # Only count "supported" branches on the dashboard (enabled + non-EOL).
    # EOL branches remain in DB for auditability.
    @branch_targets = BranchTarget.where(enabled: true, maintenance_status: %w[normal security]).order(name: :asc)
    @config = BotConfig.instance
    @events = filtered_events
    @event_filter = params[:status]

    # Patch bundles stats
    @patch_bundles_count = PatchBundle.count
    @pending_reviews_count = PatchBundle.ready_for_review.count

    # AI insights data
    @llm_bundles_count = PatchBundle.llm_resolved.count
    @ai_recommendations_count = PatchBundle.llm_resolved.ready_for_review.count
    @high_confidence_count = PatchBundle.with_high_confidence.count
    @medium_confidence_count = PatchBundle.with_medium_confidence.count
    @low_confidence_count = PatchBundle.with_low_confidence.count
    @recent_llm_recommendations = PatchBundle.llm_resolved.order(created_at: :desc).limit(5)

    # Trend calculations (today vs yesterday)
    @open_prs_trend = calculate_trend(PullRequest.where(status: "open"), :created_at)
    @candidates_trend = calculate_trend(CandidateBump, :created_at)
    @bundles_trend = calculate_trend(PatchBundle, :created_at)
  end

  def stats
    render json: {
      open_prs: {
        value: PullRequest.where(status: "open").count,
        trend: calculate_trend(PullRequest.where(status: "open"), :created_at),
        trend_period: "today"
      },
      branch_targets: {
        value: BranchTarget.where(enabled: true, maintenance_status: %w[normal security]).count
      },
      recent_candidates: {
        value: CandidateBump.where("created_at > ?", 7.days.ago).count,
        trend: calculate_trend(CandidateBump, :created_at),
        trend_period: "today"
      },
      patch_bundles: {
        value: PatchBundle.count,
        trend: calculate_trend(PatchBundle, :created_at),
        trend_period: "today"
      },
      # Additional stats for notifications
      pending_reviews: {
        value: PatchBundle.ready_for_review.count
      },
      new_advisories_24h: {
        value: Advisory.where("created_at > ?", 24.hours.ago).count
      }
    }
  end

  def events
    @events = filtered_events
    @event_filter = params[:status]

    render partial: "admin/dashboard/events_frame", locals: { events: @events, event_filter: @event_filter }
  end

  def trigger_advisory_sync
    EvaluateOsvVulnerabilitiesJob.perform_later
    SystemEvent.create!(
      kind: "manual_sync_triggered",
      status: "ok",
      message: "Manual advisory sync triggered by admin",
      occurred_at: Time.current
    )
    redirect_to admin_root_path, notice: "Advisory sync job queued successfully."
  end

  def trigger_reevaluation
    ReevaluateAwaitingFixJob.perform_later
    SystemEvent.create!(
      kind: "manual_reevaluation_triggered",
      status: "ok",
      message: "Manual re-evaluation triggered by admin",
      occurred_at: Time.current
    )
    redirect_to admin_root_path, notice: "Re-evaluation job queued successfully."
  end

  private

  def filtered_events
    events = SystemEvent.order(occurred_at: :desc).limit(50)
    events = events.where(status: params[:status]) if params[:status].present?
    events
  end

  def calculate_trend(scope, date_column)
    today_start = Time.current.beginning_of_day
    yesterday_start = 1.day.ago.beginning_of_day
    yesterday_end = today_start

    today_count = scope.where("#{date_column} >= ?", today_start).count
    yesterday_count = scope.where("#{date_column} >= ? AND #{date_column} < ?", yesterday_start, yesterday_end).count

    today_count - yesterday_count
  end
end
