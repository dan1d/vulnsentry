# frozen_string_literal: true

# Normalizes gem versions by stripping platform-specific suffixes.
#
# Gem versions in Gemfile.lock can include platform suffixes like:
#   - nokogiri (1.18.10-x86_64-linux-gnu)
#   - nokogiri (1.18.10-x86_64-darwin)
#   - nokogiri (1.18.10-arm64-darwin)
#
# These can't be parsed by Gem::Version directly, so we strip the suffix
# to get the base version for vulnerability checking.
class GemVersionNormalizer
  # Common platform patterns that appear after the version number
  PLATFORM_PATTERNS = [
    /-x86_64-.+$/,       # x86_64-linux, x86_64-linux-gnu, x86_64-darwin
    /-x86-.+$/,          # x86-mingw32, x86-linux
    /-arm64-.+$/,        # arm64-darwin
    /-aarch64-.+$/,      # aarch64-linux
    /-mingw\d*$/,        # mingw32
    /-mswin\d*$/,        # mswin32, mswin64
    /-java$/,            # java platform
    /-jruby$/,           # jruby platform
    /-universal-.+$/     # universal-darwin
  ].freeze

  # Normalize a version string by removing platform suffix.
  #
  # @param version [String] The version string, possibly with platform suffix
  # @return [String] The base version without platform suffix
  def self.normalize(version)
    return version if version.blank?

    normalized = version.to_s.dup

    PLATFORM_PATTERNS.each do |pattern|
      normalized.gsub!(pattern, "")
    end

    normalized
  end

  # Parse a version string into a Gem::Version, handling platform suffixes.
  #
  # @param version [String] The version string
  # @return [Gem::Version] The parsed version
  # @raise [ArgumentError] If the normalized version is still invalid
  def self.parse(version)
    Gem::Version.new(normalize(version))
  end
end
