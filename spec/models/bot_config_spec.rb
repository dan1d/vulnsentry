require "rails_helper"

RSpec.describe BotConfig, type: :model do
  describe ".instance" do
    it "returns a singleton row" do
      config1 = described_class.instance
      config2 = described_class.instance

      expect(config1).to be_persisted
      expect(config2).to eq(config1)
      expect(described_class.where(singleton: true).count).to eq(1)
    end
  end

  describe "singleton validation" do
    it "does not allow multiple singleton rows" do
      create(:bot_config, singleton: true)
      other = build(:bot_config, singleton: true)

      expect(other).not_to be_valid
      expect(other.errors[:singleton]).to include("must be unique")
    end
  end
end
