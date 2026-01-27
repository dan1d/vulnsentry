require "rails_helper"

RSpec.describe CreatePatchBundlePrJob, type: :job do
  let(:bundle) { create(:patch_bundle, :approved) }

  before do
    create(:bot_config)
    create(:bundled_advisory, patch_bundle: bundle)
  end

  describe "#perform" do
    context "when successful" do
      let(:creator) { instance_double(Github::RubyCorePrCreator) }

      before do
        allow(Github::RubyCorePrCreator).to receive(:new).and_return(creator)
        allow(creator).to receive(:create_for_patch_bundle!).and_return({
          number: 12345,
          url: "https://github.com/ruby/ruby/pull/12345",
          head_branch: "bump-rexml-3.2.7-ruby_3_0"
        })
      end

      it "creates a PullRequest record" do
        expect {
          described_class.perform_now(bundle.id)
        }.to change(PullRequest, :count).by(1)
      end

      it "updates the bundle state to submitted" do
        described_class.perform_now(bundle.id)

        bundle.reload
        expect(bundle.state).to eq("submitted")
        expect(bundle.created_pr_at).to be_present
      end

      it "creates a success system event" do
        described_class.perform_now(bundle.id)

        event = SystemEvent.last
        expect(event.kind).to eq("create_patch_bundle_pr")
        expect(event.status).to eq("ok")
        expect(event.payload["pr_number"]).to eq(12345)
      end
    end

    context "when emergency stop is enabled" do
      before do
        BotConfig.instance.update!(emergency_stop: true)
      end

      it "does nothing" do
        expect {
          described_class.perform_now(bundle.id)
        }.not_to change(PullRequest, :count)
      end
    end

    context "when bundle is not approved" do
      before do
        bundle.update!(state: "ready_for_review")
      end

      it "does nothing" do
        expect {
          described_class.perform_now(bundle.id)
        }.not_to change(PullRequest, :count)
      end
    end

    context "when bundle already has a PR" do
      let(:creator) { instance_double(Github::RubyCorePrCreator) }

      before do
        create(:pull_request, patch_bundle: bundle, status: pr_status)
        allow(Github::RubyCorePrCreator).to receive(:new).and_return(creator)
        allow(creator).to receive(:create_for_patch_bundle!).and_return({
          number: 99999,
          url: "https://github.com/ruby/ruby/pull/99999",
          head_branch: "bump-rexml-3.2.7-ruby_3_0-2"
        })
      end

      context "when PR is open" do
        let(:pr_status) { "open" }

        it "does nothing" do
          expect {
            described_class.perform_now(bundle.id)
          }.not_to change(PullRequest, :count)
        end
      end

      context "when PR is merged" do
        let(:pr_status) { "merged" }

        it "does nothing" do
          expect {
            described_class.perform_now(bundle.id)
          }.not_to change(PullRequest, :count)
        end
      end

      context "when PR is closed" do
        let(:pr_status) { "closed" }

        it "recreates by updating the existing PullRequest record" do
          pr = bundle.pull_request

          expect {
            described_class.perform_now(bundle.id)
          }.not_to change(PullRequest, :count)

          pr.reload
          expect(pr.pr_number).to eq(99999)
          expect(pr.status).to eq("open")
        end
      end
    end

    context "when PR creation fails" do
      before do
        creator = instance_double(Github::RubyCorePrCreator)
        allow(Github::RubyCorePrCreator).to receive(:new).and_return(creator)
        allow(creator).to receive(:create_for_patch_bundle!).and_raise(
          Github::RubyCorePrCreator::Error.new("Git clone failed")
        )
      end

      it "updates bundle state to failed" do
        expect {
          described_class.perform_now(bundle.id)
        }.to raise_error(Github::RubyCorePrCreator::Error)

        bundle.reload
        expect(bundle.state).to eq("failed")
        expect(bundle.blocked_reason).to eq("Github::RubyCorePrCreator::Error")
        expect(bundle.review_notes).to include("Git clone failed")
      end

      it "creates a failure system event" do
        expect {
          described_class.perform_now(bundle.id)
        }.to raise_error(Github::RubyCorePrCreator::Error)

        event = SystemEvent.last
        expect(event.kind).to eq("create_patch_bundle_pr")
        expect(event.status).to eq("failed")
      end
    end
  end
end
