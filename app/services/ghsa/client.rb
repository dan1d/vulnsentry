module Ghsa
  class Client
    include CacheableApi

    class Error < StandardError; end

    self.cache_namespace = "ghsa"

    # We use gh CLI (authenticated via GH_TOKEN) to call GitHub GraphQL.
    def initialize(gh: Github::GhCli.new)
      @gh = gh
    end

    # Returns an array of vulnerability hashes:
    # [{ "ghsaId" => "...", "cve" => "CVE-...", "advisoryUrl" => "...",
    #    "vulnerableVersionRange" => "...", "firstPatchedVersion" => "x.y.z" }, ...]
    #
    # Note: This queries the GitHub Advisory Database for RubyGems packages.
    # Results are cached for 15 minutes by default. Use force_refresh: true
    # to bypass the cache.
    def vulnerabilities_for_rubygem(gem_name:, limit: 50, force_refresh: false)
      cached(:ghsa_query, gem_name, limit, force: force_refresh) do
        fetch_from_api(gem_name: gem_name, limit: limit)
      end
    end

    private

    def fetch_from_api(gem_name:, limit:)
      query = <<~GRAPHQL
        query($ecosystem: SecurityAdvisoryEcosystem!, $package: String!, $first: Int!) {
          securityVulnerabilities(ecosystem: $ecosystem, package: $package, first: $first) {
            nodes {
              vulnerableVersionRange
              firstPatchedVersion { identifier }
              advisory {
                ghsaId
                permalink
                identifiers { type value }
                publishedAt
                updatedAt
              }
              package { name ecosystem }
            }
          }
        }
      GRAPHQL

      data = @gh.json!(
        "api",
        "graphql",
        "-f",
        "query=#{query}",
        "-f",
        "ecosystem=RUBYGEMS",
        "-f",
        "package=#{gem_name}",
        "-F",
        "first=#{limit}"
      )

      nodes = data.dig("data", "securityVulnerabilities", "nodes") || []
      nodes.map do |n|
        advisory = n.fetch("advisory")
        identifiers = Array(advisory["identifiers"])
        cve = identifiers.find { |i| i["type"] == "CVE" }&.fetch("value", nil)
        {
          "ghsaId" => advisory.fetch("ghsaId"),
          "cve" => cve,
          "advisoryUrl" => advisory.fetch("permalink"),
          "vulnerableVersionRange" => n.fetch("vulnerableVersionRange"),
          "firstPatchedVersion" => n.dig("firstPatchedVersion", "identifier"),
          "publishedAt" => advisory["publishedAt"],
          "updatedAt" => advisory["updatedAt"]
        }
      end
    rescue Github::GhCli::CommandError, KeyError => e
      raise Error, e.message
    end
  end
end
