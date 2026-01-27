require "rails_helper"

RSpec.describe BundledAdvisory, type: :model do
  subject(:bundled_advisory) { build(:bundled_advisory) }

  it { is_expected.to belong_to(:patch_bundle) }
  it { is_expected.to belong_to(:advisory) }

  it { is_expected.to validate_presence_of(:patch_bundle) }
  it { is_expected.to validate_presence_of(:advisory) }

  describe "uniqueness" do
    it "prevents duplicate advisory links for the same patch bundle" do
      patch_bundle = create(:patch_bundle)
      advisory = create(:advisory)
      create(:bundled_advisory, patch_bundle: patch_bundle, advisory: advisory)

      duplicate = build(:bundled_advisory, patch_bundle: patch_bundle, advisory: advisory)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:advisory_id]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let(:patch_bundle) { create(:patch_bundle) }

    describe ".included" do
      it "returns advisories included in the fix" do
        included = create(:bundled_advisory, patch_bundle: patch_bundle, included_in_fix: true)
        excluded = create(:bundled_advisory, :excluded, patch_bundle: patch_bundle)

        expect(described_class.included).to include(included)
        expect(described_class.included).not_to include(excluded)
      end
    end

    describe ".excluded" do
      it "returns advisories excluded from the fix" do
        included = create(:bundled_advisory, patch_bundle: patch_bundle, included_in_fix: true)
        excluded = create(:bundled_advisory, :excluded, patch_bundle: patch_bundle)

        expect(described_class.excluded).to include(excluded)
        expect(described_class.excluded).not_to include(included)
      end
    end
  end

  describe "#cve" do
    it "delegates to advisory" do
      advisory = build(:advisory, cve: "CVE-2024-12345")
      bundled_advisory = build(:bundled_advisory, advisory: advisory)

      expect(bundled_advisory.cve).to eq("CVE-2024-12345")
    end
  end

  describe "#source" do
    it "delegates to advisory" do
      advisory = build(:advisory, source: "ghsa")
      bundled_advisory = build(:bundled_advisory, advisory: advisory)

      expect(bundled_advisory.source).to eq("ghsa")
    end
  end
end
