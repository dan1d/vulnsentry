require "rails_helper"

RSpec.describe Ai::PatchVersionResolver do
  subject(:resolver) { described_class.new(client: mock_client) }

  let(:mock_client) { instance_double(Ai::DeepseekClient) }
  let(:patch_bundle) { create(:patch_bundle, :with_advisories, gem_name: "rexml", current_version: "3.2.5") }
  let(:bundled_advisories) { patch_bundle.bundled_advisories }

  describe "#enabled?" do
    it "delegates to client" do
      allow(mock_client).to receive(:enabled?).and_return(true)
      expect(resolver.enabled?).to be true
    end
  end

  describe "#resolve" do
    context "when LLM is enabled and returns confident recommendation" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!).and_return({
          "recommended_version" => "3.2.8",
          "confidence" => "high",
          "reasoning" => "All advisories fixed by 3.2.8",
          "excluded_advisories" => [],
          "exclusion_reason" => nil
        })
      end

      it "returns a confident recommendation" do
        result = resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories
        )

        expect(result.recommended_version).to eq("3.2.8")
        expect(result.confidence).to eq("high")
        expect(result.confident?).to be true
      end
    end

    context "when LLM is enabled and returns low confidence" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!).and_return({
          "recommended_version" => "3.3.0",
          "confidence" => "low",
          "reasoning" => "Major version bump required",
          "excluded_advisories" => ["CVE-2024-123"],
          "exclusion_reason" => "requires major version bump"
        })
      end

      it "returns a non-confident recommendation" do
        result = resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories
        )

        expect(result.recommended_version).to eq("3.3.0")
        expect(result.confident?).to be false
        expect(result.excluded_advisories).to eq(["CVE-2024-123"])
      end
    end

    context "when LLM is disabled" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(false)
      end

      it "falls back to simple version resolution" do
        # Set up bundled advisories with suggested versions
        bundled_advisories.first.update!(suggested_fix_version: "3.2.7")
        bundled_advisories.last.update!(suggested_fix_version: "3.2.8")

        result = resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories.reload
        )

        expect(result.recommended_version).to eq("3.2.8")
        expect(result.confidence).to eq("high")
      end
    end

    context "when LLM raises an error" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!).and_raise(Ai::DeepseekClient::Error.new("API error"))
      end

      it "falls back to simple resolution" do
        bundled_advisories.first.update!(suggested_fix_version: "3.2.7")
        bundled_advisories.last.update!(suggested_fix_version: "3.2.8")

        result = resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories.reload
        )

        expect(result.recommended_version).to eq("3.2.8")
      end
    end

    context "when no fix versions are available" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(false)
        bundled_advisories.update_all(suggested_fix_version: nil)
      end

      it "returns a low confidence result" do
        result = resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories.reload
        )

        expect(result.confident?).to be false
        expect(result.reasoning).to include("No fix versions available")
      end
    end
  end

  describe Ai::PatchVersionResolver::Recommendation do
    describe "#confident?" do
      it "returns true for high confidence" do
        rec = described_class.new("confidence" => "high")
        expect(rec.confident?).to be true
      end

      it "returns true for medium confidence" do
        rec = described_class.new("confidence" => "medium")
        expect(rec.confident?).to be true
      end

      it "returns false for low confidence" do
        rec = described_class.new("confidence" => "low")
        expect(rec.confident?).to be false
      end
    end

    describe "#to_h" do
      it "converts recommendation to hash" do
        rec = described_class.new(
          "recommended_version" => "3.2.8",
          "confidence" => "high",
          "reasoning" => "test",
          "excluded_advisories" => ["CVE-1"],
          "exclusion_reason" => "reason"
        )

        expect(rec.to_h).to eq({
          recommended_version: "3.2.8",
          confidence: "high",
          reasoning: "test",
          excluded_advisories: ["CVE-1"],
          exclusion_reason: "reason"
        })
      end
    end
  end
end
