# Re-evaluates a single PatchBundle to check if:
# 1. Any linked advisory now has a fix version available
# 2. The target version resolution has changed
# 3. Rate limits have cleared
class ReevaluatePatchBundleJob < ApplicationJob
  queue_as :default

  def perform(patch_bundle_id)
    bundle = PatchBundle.find_by(id: patch_bundle_id)
    return unless bundle

    # Skip if already in a terminal state
    return if %w[submitted rejected].include?(bundle.state)

    builder = Evaluation::PatchBundleBuilder.new
    builder.reevaluate!(bundle)

    log_reevaluation(bundle)
  rescue StandardError => e
    log_error(bundle, e)
    raise
  end

  private

  def log_reevaluation(bundle)
    SystemEvent.create!(
      kind: "patch_bundle_reevaluation",
      status: "ok",
      message: "Re-evaluated #{bundle.gem_name} on #{bundle.base_branch}",
      payload: {
        patch_bundle_id: bundle.id,
        gem_name: bundle.gem_name,
        base_branch: bundle.base_branch,
        new_state: bundle.state,
        target_version: bundle.target_version
      },
      occurred_at: Time.current
    )
  end

  def log_error(bundle, error)
    SystemEvent.create!(
      kind: "patch_bundle_reevaluation",
      status: "failed",
      message: error.message,
      payload: {
        patch_bundle_id: bundle&.id,
        error_class: error.class.name
      },
      occurred_at: Time.current
    )
  end
end
