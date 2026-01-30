require "rails_helper"

RSpec.describe Ai::AdvisoryAnalyzer do
  subject(:analyzer) { described_class.new(client: mock_client) }

  let(:mock_client) { instance_double(Ai::DeepseekClient) }

  let(:critical_advisory) do
    create(:advisory,
      gem_name: "rexml",
      cve: "CVE-2024-001",
      severity: "critical",
      source: "ruby_lang"
    )
  end

  let(:high_advisory) do
    create(:advisory,
      gem_name: "net-http",
      cve: "CVE-2024-002",
      severity: "high",
      source: "ghsa"
    )
  end

  let(:medium_advisory) do
    create(:advisory,
      gem_name: "json",
      cve: "CVE-2024-003",
      severity: "medium",
      source: "osv"
    )
  end

  describe "#enabled?" do
    it "delegates to client" do
      allow(mock_client).to receive(:enabled?).and_return(true)
      expect(analyzer.enabled?).to be true
    end

    it "returns false when client is disabled" do
      allow(mock_client).to receive(:enabled?).and_return(false)
      expect(analyzer.enabled?).to be false
    end
  end

  describe "#analyze" do
    context "when LLM is enabled and returns valid analysis" do
      let(:llm_response) do
        {
          "prioritized_advisories" => [
            {
              "cve" => "CVE-2024-001",
              "gem_name" => "rexml",
              "priority_rank" => 1,
              "risk_score" => 9,
              "severity" => "CRITICAL",
              "exploitability" => "remote",
              "impact_assessment" => "Remote code execution possible",
              "reasoning" => "Critical RCE vulnerability in widely-used gem"
            },
            {
              "cve" => "CVE-2024-002",
              "gem_name" => "net-http",
              "priority_rank" => 2,
              "risk_score" => 7,
              "severity" => "HIGH",
              "exploitability" => "requires_config",
              "impact_assessment" => "Data exposure under specific conditions",
              "reasoning" => "High severity but requires specific configuration"
            }
          ],
          "summary" => "2 advisories analyzed. 1 critical, 1 high severity.",
          "high_priority_count" => 2,
          "risk_assessment" => "High overall risk due to critical RCE vulnerability",
          "recommended_actions" => [
            "Patch rexml immediately",
            "Review net-http configuration"
          ]
        }
      end

      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!).and_return(llm_response)
      end

      it "returns prioritized analysis result" do
        result = analyzer.analyze([ critical_advisory, high_advisory ])

        expect(result).to be_a(Ai::AdvisoryAnalyzer::AnalysisResult)
        expect(result.prioritized_advisories.size).to eq(2)
        expect(result.summary).to include("2 advisories")
        expect(result.high_priority_count).to eq(2)
        expect(result.urgent?).to be true
      end

      it "returns advisories sorted by priority rank" do
        result = analyzer.analyze([ critical_advisory, high_advisory ])

        priorities = result.prioritized_advisories.map { |a| a["priority_rank"] }
        expect(priorities).to eq([ 1, 2 ])
      end

      it "includes risk scores and reasoning" do
        result = analyzer.analyze([ critical_advisory, high_advisory ])

        first = result.prioritized_advisories.first
        expect(first["risk_score"]).to eq(9)
        expect(first["reasoning"]).to include("Critical RCE")
      end

      it "includes recommended actions" do
        result = analyzer.analyze([ critical_advisory, high_advisory ])

        expect(result.recommended_actions).to include("Patch rexml immediately")
      end
    end

    context "when LLM is disabled" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(false)
      end

      it "falls back to severity-based analysis" do
        result = analyzer.analyze([ medium_advisory, critical_advisory, high_advisory ])

        expect(result.summary).to include("Fallback analysis")
        expect(result.prioritized_advisories.size).to eq(3)

        # Should be sorted by severity (critical first)
        first = result.prioritized_advisories.first
        expect(first["cve"]).to eq("CVE-2024-001") # critical
        expect(first["priority_rank"]).to eq(1)
        expect(first["risk_score"]).to eq(10) # critical = 10
      end

      it "counts high priority items correctly" do
        result = analyzer.analyze([ medium_advisory, critical_advisory, high_advisory ])

        # critical (10) and high (8) are >= 6
        expect(result.high_priority_count).to eq(2)
      end

      it "includes fallback recommended actions" do
        result = analyzer.analyze([ critical_advisory ])

        expect(result.recommended_actions).to include("Review high-severity advisories first")
      end
    end

    context "when LLM raises an error" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!).and_raise(
          Ai::DeepseekClient::Error.new("API error")
        )
      end

      it "falls back to severity-based analysis" do
        result = analyzer.analyze([ critical_advisory, high_advisory ])

        expect(result.summary).to include("Fallback analysis")
        expect(result.prioritized_advisories.size).to eq(2)
      end
    end

    context "with empty advisory list" do
      before do
        allow(mock_client).to receive(:enabled?).and_return(true)
        allow(mock_client).to receive(:extract_json!) # stub but shouldn't be called
      end

      it "returns empty result without calling LLM" do
        result = analyzer.analyze([])

        expect(mock_client).not_to have_received(:extract_json!)
        expect(result.prioritized_advisories).to be_empty
        expect(result.summary).to eq("No advisories to analyze")
        expect(result.urgent?).to be false
      end
    end
  end

  describe "#analyze_by_gem" do
    before do
      allow(mock_client).to receive(:enabled?).and_return(false)
    end

    it "groups analysis by gem name" do
      advisories = [ critical_advisory, high_advisory, medium_advisory ]
      results = analyzer.analyze_by_gem(advisories)

      expect(results.keys).to match_array(%w[rexml net-http json])
      expect(results["rexml"]).to be_a(Ai::AdvisoryAnalyzer::AnalysisResult)
    end

    it "returns empty hash for empty input" do
      results = analyzer.analyze_by_gem([])
      expect(results).to eq({})
    end
  end

  describe Ai::AdvisoryAnalyzer::AnalysisResult do
    describe "#urgent?" do
      it "returns true when high_priority_count > 0" do
        result = described_class.new("high_priority_count" => 2)
        expect(result.urgent?).to be true
      end

      it "returns false when high_priority_count is 0" do
        result = described_class.new("high_priority_count" => 0)
        expect(result.urgent?).to be false
      end
    end

    describe "#to_h" do
      it "converts to hash with all fields" do
        result = described_class.new(
          "prioritized_advisories" => [ { "cve" => "CVE-1" } ],
          "summary" => "test summary",
          "high_priority_count" => 1,
          "recommended_actions" => [ "action 1" ],
          "risk_assessment" => "high risk"
        )

        hash = result.to_h
        expect(hash[:prioritized_advisories]).to eq([ { "cve" => "CVE-1" } ])
        expect(hash[:summary]).to eq("test summary")
        expect(hash[:high_priority_count]).to eq(1)
        expect(hash[:recommended_actions]).to eq([ "action 1" ])
        expect(hash[:risk_assessment]).to eq("high risk")
      end
    end
  end

  describe Ai::AdvisoryAnalyzer::PrioritizedAdvisory do
    describe "#critical?" do
      it "returns true for risk_score >= 8" do
        pa = described_class.new("risk_score" => 9)
        expect(pa.critical?).to be true
      end

      it "returns false for risk_score < 8" do
        pa = described_class.new("risk_score" => 7)
        expect(pa.critical?).to be false
      end

      it "returns false for nil risk_score" do
        pa = described_class.new({})
        expect(pa.critical?).to be false
      end
    end

    describe "#high?" do
      it "returns true for risk_score >= 6" do
        pa = described_class.new("risk_score" => 6)
        expect(pa.high?).to be true
      end

      it "returns false for risk_score < 6" do
        pa = described_class.new("risk_score" => 5)
        expect(pa.high?).to be false
      end
    end

    describe "#to_h" do
      it "includes all fields" do
        pa = described_class.new(
          "cve" => "CVE-2024-001",
          "gem_name" => "rexml",
          "priority_rank" => 1,
          "risk_score" => 9,
          "reasoning" => "Critical vulnerability",
          "severity" => "CRITICAL",
          "exploitability" => "remote",
          "impact_assessment" => "RCE possible"
        )

        hash = pa.to_h
        expect(hash[:cve]).to eq("CVE-2024-001")
        expect(hash[:gem_name]).to eq("rexml")
        expect(hash[:priority_rank]).to eq(1)
        expect(hash[:risk_score]).to eq(9)
        expect(hash[:reasoning]).to eq("Critical vulnerability")
        expect(hash[:severity]).to eq("CRITICAL")
        expect(hash[:exploitability]).to eq("remote")
        expect(hash[:impact_assessment]).to eq("RCE possible")
      end
    end
  end
end
