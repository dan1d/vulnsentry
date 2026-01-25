module Advisories
  class GhsaIngestor
    def initialize(ghsa: Ghsa::Client.new, ruby_lang_rss: RubyLang::NewsRss.new)
      @ghsa = ghsa
      @ruby_lang_rss = ruby_lang_rss
    end

    # Returns array of Advisory for GHSA vulns affecting gem@version.
    def ingest_for_version(gem_name:, version:)
      vulns = @ghsa.vulnerabilities_for_rubygem(gem_name: gem_name)
      applicable = vulns.select { |v| Ghsa::Vulnerability.affected?(v.fetch("vulnerableVersionRange"), version) }

      applicable.map do |v|
        ghsa_id = v.fetch("ghsaId")
        fingerprint = "ghsa:#{ghsa_id}"
        advisory = Advisory.find_or_initialize_by(fingerprint: fingerprint)
        advisory.gem_name = gem_name
        advisory.source = "ghsa"
        advisory.cve = v["cve"]
        ruby_lang_url = @ruby_lang_rss.find_announcement_url_by_cve(advisory.cve)
        advisory.advisory_url = ruby_lang_url.presence || v.fetch("advisoryUrl")
        advisory.raw = v
        advisory.raw["ruby_lang_url"] = ruby_lang_url if ruby_lang_url.present?
        advisory.save!
        advisory
      end
    end
  end
end
