require "rails_helper"

RSpec.describe PatchBundle, type: :model do
  subject(:patch_bundle) { build(:patch_bundle) }

  it { is_expected.to belong_to(:branch_target) }
  it { is_expected.to have_many(:bundled_advisories).dependent(:destroy) }
  it { is_expected.to have_many(:advisories).through(:bundled_advisories) }
  it { is_expected.to have_one(:pull_request).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:base_branch) }
  it { is_expected.to validate_presence_of(:gem_name) }
  it { is_expected.to validate_presence_of(:current_version) }
  it { is_expected.to validate_presence_of(:state) }
  it { is_expected.to validate_inclusion_of(:state).in_array(described_class::STATES) }
  it { is_expected.to validate_inclusion_of(:resolution_source).in_array(described_class::RESOLUTION_SOURCES).allow_nil }

  describe "#has_fix?" do
    it "returns true when target_version differs from current_version" do
      patch_bundle.current_version = "3.2.5"
      patch_bundle.target_version = "3.2.7"
      expect(patch_bundle.has_fix?).to be true
    end

    it "returns false when target_version is nil" do
      patch_bundle.target_version = nil
      expect(patch_bundle.has_fix?).to be false
    end

    it "returns false when target_version equals current_version" do
      patch_bundle.current_version = "3.2.5"
      patch_bundle.target_version = "3.2.5"
      expect(patch_bundle.has_fix?).to be false
    end
  end

  describe "#bump_display" do
    it "shows the version bump when fix is available" do
      patch_bundle.current_version = "3.2.5"
      patch_bundle.target_version = "3.2.7"
      expect(patch_bundle.bump_display).to eq("3.2.5 → 3.2.7")
    end

    it "shows question mark when no fix is available" do
      patch_bundle.current_version = "3.2.5"
      patch_bundle.target_version = nil
      expect(patch_bundle.bump_display).to eq("3.2.5 → ?")
    end
  end

  describe "scopes" do
    describe ".awaiting_fix" do
      it "returns bundles in awaiting_fix state" do
        awaiting = create(:patch_bundle, :awaiting_fix)
        ready = create(:patch_bundle, state: "ready_for_review")

        expect(described_class.awaiting_fix).to include(awaiting)
        expect(described_class.awaiting_fix).not_to include(ready)
      end
    end

    describe ".needs_reevaluation" do
      it "returns bundles that need re-evaluation" do
        old_awaiting = create(:patch_bundle, :awaiting_fix, last_evaluated_at: 48.hours.ago)
        recent_awaiting = create(:patch_bundle, :awaiting_fix, last_evaluated_at: 1.hour.ago)
        never_evaluated = create(:patch_bundle, :awaiting_fix, last_evaluated_at: nil)

        result = described_class.needs_reevaluation(24)

        expect(result).to include(old_awaiting)
        expect(result).to include(never_evaluated)
        expect(result).not_to include(recent_awaiting)
      end
    end
  end
end
