module Advisories
  class OsvIngestor
    def initialize(osv: Osv::Client.new, ruby_lang_rss: RubyLang::NewsRss.new)
      @osv = osv
      @ruby_lang_rss = ruby_lang_rss
    end

    # Creates or updates Advisory records for vulns affecting gem@version.
    # Returns array of Advisory records.
    def ingest_for_version(gem_name:, version:)
      data = @osv.query_rubygems(gem_name: gem_name, version: version)
      vulns = Array(data["vulns"])

      vulns.map do |raw|
        osv_id = raw.fetch("id")
        fingerprint = "osv:#{osv_id}"

        advisory = Advisory.find_or_initialize_by(fingerprint: fingerprint)
        advisory.gem_name = gem_name
        advisory.source = "osv"
        advisory.cve = Osv::Vulnerability.pick_cve(raw)
        ruby_lang_url = @ruby_lang_rss.find_announcement_url_by_cve(advisory.cve)
        advisory.advisory_url = ruby_lang_url.presence || Osv::Vulnerability.pick_advisory_url(raw)
        advisory.raw = raw
        advisory.raw["ruby_lang_url"] = ruby_lang_url if ruby_lang_url.present?
        advisory.published_at = raw["published"]
        advisory.withdrawn_at = raw["withdrawn"]
        advisory.save!
        advisory
      end
    end
  end
end
