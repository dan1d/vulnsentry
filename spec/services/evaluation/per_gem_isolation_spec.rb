require "rails_helper"

RSpec.describe "Evaluator per-gem isolation" do
  it "continues when one gem's candidate build raises unexpectedly" do
    branch = create(:branch_target, name: "master", enabled: true, maintenance_status: "normal")

    # Two entries in bundled_gems.
    bundled = <<~TXT
      rexml 3.4.4 https://github.com/ruby/rexml
      rake 13.3.1 https://github.com/ruby/rake
    TXT

    fetcher = instance_double(RubyCore::BundledGemsFetcher)
    allow(fetcher).to receive(:fetch).and_return(bundled)

    advisory_chain = instance_double(Evaluation::BundledGemsAdvisoryChain)

    adv1 = Advisory.create!(
      fingerprint: "osv:OSV-1",
      gem_name: "rexml",
      source: "osv",
      raw: { "affected" => [] }
    )
    adv2 = Advisory.create!(
      fingerprint: "osv:OSV-2",
      gem_name: "rake",
      source: "osv",
      raw: { "affected" => [] }
    )

    allow(advisory_chain).to receive(:ingest_for_version) do |args|
      args[:gem_name] == "rexml" ? [ adv1 ] : [ adv2 ]
    end

    builder = instance_double(Evaluation::CandidateBumpBuilder)
    allow(builder).to receive(:build!) do |args|
      raise "boom" if args[:entry].name == "rexml"
    end

    evaluator = Evaluation::BundledGemsVulnerabilityEvaluator.new(
      fetcher: fetcher,
      advisory_chain: advisory_chain,
      candidate_builder: builder
    )
    evaluator.evaluate_branch(branch)

    expect(SystemEvent.where(kind: "candidate_build").count).to eq(1)
  end
end
