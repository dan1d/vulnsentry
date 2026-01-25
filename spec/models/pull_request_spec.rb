require "rails_helper"

RSpec.describe PullRequest, type: :model do
  subject(:pull_request) { build(:pull_request) }

  it { is_expected.to belong_to(:candidate_bump) }

  it { is_expected.to validate_presence_of(:upstream_repo) }
  it { is_expected.to validate_presence_of(:status) }
  it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
end
