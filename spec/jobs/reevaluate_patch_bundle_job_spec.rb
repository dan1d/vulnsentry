require "rails_helper"

RSpec.describe ReevaluatePatchBundleJob, type: :job do
  describe "#perform" do
    let(:bundle) { create(:patch_bundle, :awaiting_fix) }

    before do
      create(:bundled_advisory, patch_bundle: bundle)
    end

    it "calls the builder's reevaluate! method" do
      builder = instance_double(Evaluation::PatchBundleBuilder)
      allow(Evaluation::PatchBundleBuilder).to receive(:new).and_return(builder)
      allow(builder).to receive(:reevaluate!)

      described_class.perform_now(bundle.id)

      expect(builder).to have_received(:reevaluate!).with(bundle)
    end

    it "creates a success system event" do
      builder = instance_double(Evaluation::PatchBundleBuilder)
      allow(Evaluation::PatchBundleBuilder).to receive(:new).and_return(builder)
      allow(builder).to receive(:reevaluate!)

      described_class.perform_now(bundle.id)

      event = SystemEvent.last
      expect(event.kind).to eq("patch_bundle_reevaluation")
      expect(event.status).to eq("ok")
    end

    it "does nothing if bundle is not found" do
      expect {
        described_class.perform_now(999999)
      }.not_to raise_error
    end

    it "skips bundles in terminal states" do
      bundle.update!(state: "submitted")

      builder = instance_double(Evaluation::PatchBundleBuilder)
      allow(Evaluation::PatchBundleBuilder).to receive(:new).and_return(builder)
      allow(builder).to receive(:reevaluate!)

      described_class.perform_now(bundle.id)

      expect(builder).not_to have_received(:reevaluate!)
    end

    context "when an error occurs" do
      it "creates a failure system event and re-raises" do
        builder = instance_double(Evaluation::PatchBundleBuilder)
        allow(Evaluation::PatchBundleBuilder).to receive(:new).and_return(builder)
        allow(builder).to receive(:reevaluate!).and_raise(StandardError.new("Test error"))

        expect {
          described_class.perform_now(bundle.id)
        }.to raise_error(StandardError, "Test error")

        event = SystemEvent.last
        expect(event.kind).to eq("patch_bundle_reevaluation")
        expect(event.status).to eq("failed")
        expect(event.message).to eq("Test error")
      end
    end
  end
end
