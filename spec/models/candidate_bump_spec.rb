require "rails_helper"

RSpec.describe CandidateBump, type: :model do
  subject(:candidate_bump) { build(:candidate_bump) }

  it { is_expected.to belong_to(:advisory) }
  it { is_expected.to belong_to(:branch_target) }
  it { is_expected.to have_one(:pull_request).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:base_branch) }
  it { is_expected.to validate_presence_of(:gem_name) }
  it { is_expected.to validate_presence_of(:current_version) }
  it { is_expected.to validate_presence_of(:target_version) }
  it { is_expected.to validate_presence_of(:state) }
  it { is_expected.to validate_inclusion_of(:state).in_array(described_class::STATES) }
end
