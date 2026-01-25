require "rails_helper"

RSpec.describe Evaluation::BundledGemsAdvisoryChain do
  it "falls back to OSV when GHSA fails" do
    ghsa = instance_double(Advisories::GhsaIngestor)
    osv = instance_double(Advisories::OsvIngestor)

    allow(ghsa).to receive(:ingest_for_version).and_raise(StandardError, "ghsa down")
    allow(osv).to receive(:ingest_for_version).and_return([])

    chain = described_class.new(ghsa: ghsa, osv: osv)
    advisories = chain.ingest_for_version(gem_name: "rexml", version: "3.4.4", branch: "master")

    expect(advisories).to eq([])
    expect(SystemEvent.where(kind: "ghsa_ingest").count).to eq(1)
  end
end

