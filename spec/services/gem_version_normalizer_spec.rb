# frozen_string_literal: true

require "rails_helper"

RSpec.describe GemVersionNormalizer do
  describe ".normalize" do
    it "returns simple versions unchanged" do
      expect(described_class.normalize("1.18.10")).to eq("1.18.10")
      expect(described_class.normalize("7.1.3")).to eq("7.1.3")
      expect(described_class.normalize("2.0.0.beta1")).to eq("2.0.0.beta1")
    end

    it "strips x86_64-linux suffix" do
      expect(described_class.normalize("1.18.10-x86_64-linux")).to eq("1.18.10")
    end

    it "strips x86_64-linux-gnu suffix" do
      expect(described_class.normalize("1.18.10-x86_64-linux-gnu")).to eq("1.18.10")
    end

    it "strips x86_64-darwin suffix" do
      expect(described_class.normalize("1.18.10-x86_64-darwin")).to eq("1.18.10")
    end

    it "strips arm64-darwin suffix" do
      expect(described_class.normalize("1.18.10-arm64-darwin")).to eq("1.18.10")
    end

    it "strips aarch64-linux suffix" do
      expect(described_class.normalize("1.18.10-aarch64-linux")).to eq("1.18.10")
    end

    it "strips java platform suffix" do
      expect(described_class.normalize("9.4.1-java")).to eq("9.4.1")
    end

    it "strips jruby platform suffix" do
      expect(described_class.normalize("1.0.0-jruby")).to eq("1.0.0")
    end

    it "strips universal-darwin suffix" do
      expect(described_class.normalize("1.18.10-universal-darwin")).to eq("1.18.10")
    end

    it "handles nil gracefully" do
      expect(described_class.normalize(nil)).to eq(nil)
    end

    it "handles empty string" do
      expect(described_class.normalize("")).to eq("")
    end
  end

  describe ".parse" do
    it "parses simple versions" do
      version = described_class.parse("1.18.10")
      expect(version).to eq(Gem::Version.new("1.18.10"))
    end

    it "parses platform-specific versions" do
      version = described_class.parse("1.18.10-x86_64-linux-gnu")
      expect(version).to eq(Gem::Version.new("1.18.10"))
    end

    it "allows version comparison after parsing" do
      v1 = described_class.parse("1.18.10-x86_64-linux-gnu")
      v2 = described_class.parse("1.18.11")
      expect(v2).to be > v1
    end

    it "raises ArgumentError for truly invalid versions" do
      expect { described_class.parse("not.a.version.at.all") }.to raise_error(ArgumentError)
    end
  end
end
