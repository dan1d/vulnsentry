require "json"
require "net/http"
require "uri"

module RubyGems
  class VersionResolver
    class ResolutionError < StandardError; end

    RUBYGEMS_VERSIONS_URL = "https://rubygems.org/api/v1/versions/%{gem_name}.json"

    def initialize(http: Net::HTTP)
      @http = http
    end

    # Returns Gem::Version (string acceptable by callers via to_s).
    def resolve_target_version(gem_name:, affected_requirement:, current_version:, fixed_version: nil, allow_major_minor: false)
      current = Gem::Version.new(current_version)
      affected = Gem::Requirement.new(affected_requirement)

      versions = fetch_versions(gem_name)

      if fixed_version
        fixed = Gem::Version.new(fixed_version)
        validate_candidate!(
          candidate: fixed,
          current: current,
          affected: affected,
          allow_major_minor: allow_major_minor
        )
        return fixed
      end

      versions.each do |candidate|
        next unless candidate > current
        next if candidate.prerelease?
        next if affected.satisfied_by?(candidate)

        validate_candidate!(
          candidate: candidate,
          current: current,
          affected: affected,
          allow_major_minor: allow_major_minor,
          allow_same_or_lower: false
        )
        return candidate
      end

      raise ResolutionError, "no safe version found for #{gem_name}"
    end

    private
      def fetch_versions(gem_name)
        uri = URI.parse(format(RUBYGEMS_VERSIONS_URL, gem_name: gem_name))
        response = @http.get_response(uri)
        raise ResolutionError, "rubygems request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        versions = data.map { |row| Gem::Version.new(row.fetch("number")) }
        versions.sort
      end

      def validate_candidate!(candidate:, current:, affected:, allow_major_minor:, allow_same_or_lower: true)
        if !allow_same_or_lower && candidate <= current
          raise ResolutionError, "candidate version is not newer than current"
        end

        if affected.satisfied_by?(candidate)
          raise ResolutionError, "candidate version is still affected"
        end

        if !allow_major_minor && major_or_minor_bump?(current, candidate)
          raise ResolutionError, "major/minor bump not allowed (#{current} -> #{candidate})"
        end
      end

      def major_or_minor_bump?(from, to)
        from_segments = from.segments
        to_segments = to.segments
        from_major = from_segments[0] || 0
        from_minor = from_segments[1] || 0
        to_major = to_segments[0] || 0
        to_minor = to_segments[1] || 0

        to_major != from_major || to_minor != from_minor
      end
  end
end
