class Admin::PatchBundlesController < Admin::BaseController
  def index
    per_page = (params[:per_page].presence || 20).to_i.clamp(10, 100)
    @patch_bundles = build_query.page(params[:page]).per(per_page)
  end

  def show
    @patch_bundle = PatchBundle.includes(bundled_advisories: :advisory).find(params[:id])
  end

  def update
    @patch_bundle = PatchBundle.find(params[:id])

    case params[:event]
    when "approve"
      @patch_bundle.update!(
        state: "approved",
        approved_at: Time.current,
        approved_by: current_admin_user.username
      )
      redirect_to admin_patch_bundle_path(@patch_bundle), notice: "Approved"
    when "reject"
      reason = params[:reason].presence || "rejected_by_admin"
      @patch_bundle.update!(state: "rejected", blocked_reason: reason)
      redirect_to admin_patch_bundle_path(@patch_bundle), notice: "Rejected"
    when "create_pr"
      enqueue_pr_creation!(@patch_bundle, draft: false)
      redirect_to admin_patch_bundle_path(@patch_bundle), notice: "PR creation enqueued"
    when "create_draft_pr"
      enqueue_pr_creation!(@patch_bundle, draft: true)
      redirect_to admin_patch_bundle_path(@patch_bundle), notice: "Draft PR creation enqueued"
    when "reevaluate"
      ReevaluatePatchBundleJob.perform_later(@patch_bundle.id)
      redirect_to admin_patch_bundle_path(@patch_bundle), notice: "Re-evaluation enqueued"
    when "set_target_version"
      set_manual_target_version!
      redirect_to admin_patch_bundle_path(@patch_bundle), notice: "Target version updated"
    else
      head :bad_request
    end
  end

  private

  def build_query
    scope = PatchBundle.includes(:pull_request, :bundled_advisories, branch_target: :project)
                       .order(updated_at: :desc)

    if params[:project_slug].present?
      scope = scope.joins(branch_target: :project).where(projects: { slug: params[:project_slug] })
    end
    scope = scope.where(state: params[:state]) if params[:state].present?
    scope = scope.where(base_branch: params[:base_branch]) if params[:base_branch].present?
    scope = scope.where(gem_name: params[:gem_name]) if params[:gem_name].present?

    scope
  end

  def enqueue_pr_creation!(patch_bundle, draft:)
    config = BotConfig.instance
    return if config.emergency_stop?
    return unless patch_bundle.state == "approved"

    CreatePatchBundlePrJob.perform_later(patch_bundle.id, draft: draft)
  end

  def set_manual_target_version!
    version = params[:target_version].to_s.strip
    return if version.blank?

    @patch_bundle.update!(
      target_version: version,
      resolution_source: "manual",
      state: "ready_for_review"
    )
  end
end
