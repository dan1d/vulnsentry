require "rails_helper"

RSpec.describe ReevaluateAwaitingFixJob, type: :job do
  describe "#perform" do
    let!(:old_awaiting) do
      create(:patch_bundle, :awaiting_fix, last_evaluated_at: 48.hours.ago)
    end

    let!(:recent_awaiting) do
      create(:patch_bundle, :awaiting_fix, last_evaluated_at: 1.hour.ago)
    end

    let!(:never_evaluated) do
      create(:patch_bundle, :awaiting_fix, last_evaluated_at: nil)
    end

    let!(:ready_bundle) do
      create(:patch_bundle, state: "ready_for_review", last_evaluated_at: 48.hours.ago)
    end

    it "enqueues ReevaluatePatchBundleJob for bundles needing re-evaluation" do
      expect {
        described_class.perform_now
      }.to have_enqueued_job(ReevaluatePatchBundleJob).with(old_awaiting.id)
        .and have_enqueued_job(ReevaluatePatchBundleJob).with(never_evaluated.id)
    end

    it "does not enqueue jobs for recently evaluated bundles" do
      expect {
        described_class.perform_now
      }.not_to have_enqueued_job(ReevaluatePatchBundleJob).with(recent_awaiting.id)
    end

    it "does not enqueue jobs for bundles not in awaiting_fix state" do
      expect {
        described_class.perform_now
      }.not_to have_enqueued_job(ReevaluatePatchBundleJob).with(ready_bundle.id)
    end

    it "creates a system event" do
      described_class.perform_now

      event = SystemEvent.last
      expect(event.kind).to eq("reevaluate_awaiting_fix")
      expect(event.status).to eq("ok")
      expect(event.payload["count"]).to eq(2)
    end
  end
end
