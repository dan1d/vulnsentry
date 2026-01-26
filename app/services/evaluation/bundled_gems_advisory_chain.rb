module Evaluation
  class BundledGemsAdvisoryChain
    def initialize(
      ghsa: Advisories::GhsaIngestor.new,
      osv: Advisories::OsvIngestor.new
    )
      @ghsa = ghsa
      @osv = osv
    end

    # Ruby-lang is not an independent DB source here; it refines fixed versions
    # via RubyLang::SecurityAdvisoryResolver downstream.
    #
    # Returns array of Advisory records (may be empty).
    def ingest_for_version(gem_name:, version:, branch:)
      ghsa_advisories = safe_ingest("ghsa_ingest", branch, gem_name) do
        @ghsa.ingest_for_version(gem_name: gem_name, version: version)
      end
      return ghsa_advisories if ghsa_advisories.any?

      safe_ingest("osv_ingest", branch, gem_name) do
        @osv.ingest_for_version(gem_name: gem_name, version: version)
      end
    end

    private
      def safe_ingest(kind, branch, gem_name)
        yield
      rescue StandardError => e
        SystemEvent.create!(
          kind: kind,
          status: "failed",
          message: e.message,
          payload: { branch: branch, gem_name: gem_name, class: e.class.name },
          occurred_at: Time.current
        )
        []
      end
  end
end
