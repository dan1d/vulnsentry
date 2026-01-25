require "nokogiri"

module RubyLang
  class SecurityAnnouncementParser
    class ParseError < StandardError; end

    # Extracts the recommended minimum version for a given gem from a ruby-lang
    # security announcement page.
    #
    # Returns version string or nil.
    def self.extract_fixed_version_for_gem(html:, gem_name:)
      doc = Nokogiri::HTML(html)
      text = doc.text.gsub(/\s+/, " ").strip
      gem = Regexp.escape(gem_name)

      # Common ruby-lang phrasing:
      # - "Please update REXML gem to version 3.3.9 or later."
      # - "Please update <gem> gem to version X.Y.Z or later."
      patterns = [
        /please\s+update\s+#{gem}\s+gem\s+to\s+version\s+([0-9A-Za-z\.\-_]+)\s+or\s+later/i,
        /update\s+#{gem}\s+gem\s+to\s+version\s+([0-9A-Za-z\.\-_]+)\s+or\s+later/i
      ]

      patterns.each do |re|
        m = text.match(re)
        return m[1] if m
      end

      nil
    rescue StandardError => e
      raise ParseError, e.message
    end
  end
end
