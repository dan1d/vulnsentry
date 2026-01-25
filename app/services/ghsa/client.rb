module Ghsa
  class Client
    class Error < StandardError; end

    # We use gh CLI (authenticated via GH_TOKEN) to call GitHub GraphQL.
    def initialize(gh: Github::GhCli.new)
      @gh = gh
    end

    # Returns an array of vulnerability hashes:
    # [{ "ghsaId" => "...", "cve" => "CVE-...", "advisoryUrl" => "...",
    #    "vulnerableVersionRange" => "...", "firstPatchedVersion" => "x.y.z" }, ...]
    #
    # Note: This queries the GitHub Advisory Database for RubyGems packages.
    def vulnerabilities_for_rubygem(gem_name:, limit: 50)
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
          "firstPatchedVersion" => n.dig("firstPatchedVersion", "identifier")
        }
      end
    rescue Github::GhCli::CommandError, KeyError => e
      raise Error, e.message
    end
  end
end
