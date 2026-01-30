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

    it "returns false when client is disabled" do
      allow(mock_client).to receive(:enabled?).and_return(false)
      expect(resolver.enabled?).to be false
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
          "version_analysis" => "Patch-level bump from 3.2.5 to 3.2.8",
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

      it "includes version analysis in result" do
        result = resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories
        )

        expect(result.version_analysis).to include("Patch-level bump")
      end
    end

    context "when LLM is enabled and returns low confidence" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!).and_return({
          "recommended_version" => "3.3.0",
          "confidence" => "low",
          "reasoning" => "Major version bump required",
          "excluded_advisories" => [ "CVE-2024-123" ],
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
        expect(result.excluded_advisories).to eq([ "CVE-2024-123" ])
      end
    end

    context "when LLM returns invalid recommendation (version lower than current)" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!).and_return({
          "recommended_version" => "3.2.3", # Lower than current 3.2.5
          "confidence" => "high",
          "reasoning" => "Invalid response"
        })
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
        expect(result.reasoning).to include("fallback")
      end
    end

    context "when LLM returns version that doesn't satisfy required fixes" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!).and_return({
          "recommended_version" => "3.2.6", # Lower than required 3.2.8
          "confidence" => "high",
          "reasoning" => "Invalid response"
        })
      end

      it "falls back to simple resolution when version is insufficient" do
        bundled_advisories.first.update!(suggested_fix_version: "3.2.8")
        bundled_advisories.last.update!(suggested_fix_version: "3.2.7")

        result = resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories.reload
        )

        expect(result.recommended_version).to eq("3.2.8")
        expect(result.reasoning).to include("fallback")
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

      it "returns low confidence for mixed version requirements" do
        # One patch bump, one minor bump
        bundled_advisories.first.update!(suggested_fix_version: "3.2.7")
        bundled_advisories.last.update!(suggested_fix_version: "3.3.0")

        result = resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories.reload
        )

        expect(result.confidence).to eq("low")
        expect(result.reasoning).to include("manual review")
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

      it "logs the error" do
        bundled_advisories.first.update!(suggested_fix_version: "3.2.7")

        expect(Rails.logger).to receive(:error).with(/LLM error.*API error/)

        resolver.resolve(
          gem_name: "rexml",
          base_branch: "ruby_3_0",
          current_version: "3.2.5",
          bundled_advisories: bundled_advisories.reload
        )
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

      it "returns false for nil confidence" do
        rec = described_class.new({})
        expect(rec.confident?).to be false
      end
    end

    describe "#to_h" do
      it "converts recommendation to hash" do
        rec = described_class.new(
          "recommended_version" => "3.2.8",
          "confidence" => "high",
          "reasoning" => "test",
          "version_analysis" => "patch bump",
          "excluded_advisories" => [ "CVE-1" ],
          "exclusion_reason" => "reason"
        )

        hash = rec.to_h
        expect(hash[:recommended_version]).to eq("3.2.8")
        expect(hash[:confidence]).to eq("high")
        expect(hash[:reasoning]).to eq("test")
        expect(hash[:version_analysis]).to eq("patch bump")
        expect(hash[:excluded_advisories]).to eq([ "CVE-1" ])
        expect(hash[:exclusion_reason]).to eq("reason")
      end

      it "excludes nil values with compact" do
        rec = described_class.new(
          "recommended_version" => "3.2.8",
          "confidence" => "high"
        )

        hash = rec.to_h
        expect(hash.keys).not_to include(:version_analysis)
      end
    end

    describe "#version_analysis" do
      it "returns version analysis when provided" do
        rec = described_class.new("version_analysis" => "Minor version bump required")
        expect(rec.version_analysis).to eq("Minor version bump required")
      end

      it "returns nil when not provided" do
        rec = described_class.new({})
        expect(rec.version_analysis).to be_nil
      end
    end
  end

  describe "prompt quality" do
    it "includes detailed system prompt with decision rules" do
      expect(Ai::PatchVersionResolver::SYSTEM_PROMPT).to include("SAFETY FIRST")
      expect(Ai::PatchVersionResolver::SYSTEM_PROMPT).to include("PATCH-LEVEL PREFERRED")
      expect(Ai::PatchVersionResolver::SYSTEM_PROMPT).to include("MINOR BUMP CAUTION")
      expect(Ai::PatchVersionResolver::SYSTEM_PROMPT).to include("MAJOR BUMP")
    end

    it "includes structured user prompt template" do
      expect(Ai::PatchVersionResolver::USER_PROMPT_TEMPLATE).to include("%{gem_name}")
      expect(Ai::PatchVersionResolver::USER_PROMPT_TEMPLATE).to include("%{current_version}")
      expect(Ai::PatchVersionResolver::USER_PROMPT_TEMPLATE).to include("%{base_branch}")
      expect(Ai::PatchVersionResolver::USER_PROMPT_TEMPLATE).to include("%{advisories_summary}")
    end
  end
end
