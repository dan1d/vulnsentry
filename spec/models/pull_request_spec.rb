require "rails_helper"

RSpec.describe PullRequest, type: :model do
  subject(:pull_request) { build(:pull_request) }

  it { is_expected.to belong_to(:candidate_bump).optional }
  it { is_expected.to belong_to(:patch_bundle).optional }

  it { is_expected.to validate_presence_of(:upstream_repo) }
  it { is_expected.to validate_presence_of(:status) }
  it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }

  describe "parent reference validation" do
    it "is valid with candidate_bump" do
      pr = build(:pull_request, candidate_bump: build(:candidate_bump), patch_bundle: nil)
      expect(pr).to be_valid
    end

    it "is valid with patch_bundle" do
      pr = build(:pull_request, :for_patch_bundle)
      expect(pr).to be_valid
    end

    it "is invalid without either parent" do
      pr = build(:pull_request, candidate_bump: nil, patch_bundle: nil)
      expect(pr).not_to be_valid
      expect(pr.errors[:base]).to include("must belong to either candidate_bump or patch_bundle")
    end
  end
end
