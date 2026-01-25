require "rails_helper"

RSpec.describe Advisory, type: :model do
  subject(:advisory) { build(:advisory) }

  it { is_expected.to have_many(:candidate_bumps).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:gem_name) }
  it { is_expected.to validate_presence_of(:source) }
  it { is_expected.to validate_inclusion_of(:source).in_array(described_class::SOURCES) }
  it { is_expected.to validate_presence_of(:fingerprint) }
  it { create(:advisory); is_expected.to validate_uniqueness_of(:fingerprint) }
end
