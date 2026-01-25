require "rails_helper"

RSpec.describe BranchTarget, type: :model do
  subject(:branch_target) { build(:branch_target) }

  it { is_expected.to have_many(:candidate_bumps).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:name) }
  it { create(:branch_target); is_expected.to validate_uniqueness_of(:name) }

  it { is_expected.to validate_presence_of(:maintenance_status) }
  it { is_expected.to validate_inclusion_of(:maintenance_status).in_array(described_class::MAINTENANCE_STATUSES) }
end
