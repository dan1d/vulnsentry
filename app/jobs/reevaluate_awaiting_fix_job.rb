# Periodic job that finds all PatchBundles in awaiting_fix state
# and enqueues individual re-evaluation jobs for each.
# Run daily via recurring.yml
class ReevaluateAwaitingFixJob < ApplicationJob
  queue_as :low

  def perform(hours_since_last_evaluation: 24)
    bundles = PatchBundle.needs_reevaluation(hours_since_last_evaluation)

    bundles.find_each do |bundle|
      ReevaluatePatchBundleJob.perform_later(bundle.id)
    end

    log_completion(bundles.count)
  end

  private

  def log_completion(count)
    SystemEvent.create!(
      kind: "reevaluate_awaiting_fix",
      status: "ok",
      message: "Enqueued #{count} bundles for re-evaluation",
      payload: { count: count },
      occurred_at: Time.current
    )
  end
end
