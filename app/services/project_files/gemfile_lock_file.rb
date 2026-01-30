# frozen_string_literal: true

module ProjectFiles
  # Parser for Bundler's Gemfile.lock format.
  #
  # Format example:
  #   GEM
  #     remote: https://rubygems.org/
  #     specs:
  #       actioncable (7.1.3)
  #         actionpack (= 7.1.3)
  #       actionpack (7.1.3)
  #         rack (>= 2.2.4)
  #
  # Note: Updating Gemfile.lock is complex because:
  # 1. The gem version appears in multiple places (as dependency and as spec)
  # 2. Dependency constraints may prevent simple version updates
  # 3. Ideally, `bundle update gem_name` should be run instead
  #
  # This parser supports reading and simple text-based version bumps.
  class GemfileLockFile < Base
    # Entry for a gem in the lockfile
    Entry = Data.define(:name, :version, :line_number, :raw_line) do
      def with_version(new_version)
        # Replace version in the line, e.g., "    actioncable (7.1.3)" -> "    actioncable (7.2.0)"
        updated_line = raw_line.sub(/\(#{Regexp.escape(version)}\)/, "(#{new_version})")
        self.class.new(name, new_version, line_number, updated_line)
      end
    end

    SPECS_SECTION_REGEX = /^\s{4}specs:$/
    GEM_LINE_REGEX = /^\s{4}(\S+)\s+\(([^)]+)\)$/
    PLATFORM_SECTION_REGEX = /^PLATFORMS$/
    GEM_SECTION_REGEX = /^GEM$/
    PATH_SECTION_REGEX = /^PATH$/
    GIT_SECTION_REGEX = /^GIT$/

    def entries
      @entries ||= parse_entries
    end

    def find_entry(gem_name)
      entries.find { |e| e.name == gem_name }
    end

    # Bump the version of a gem in the lockfile.
    # This does a text-based replacement which works for simple cases.
    # For complex dependency graphs, running `bundle update` is recommended.
    #
    # @param gem_name [String]
    # @param new_version [String]
    # @return [Array<String, String, String>] [new_content, old_line, new_line]
    def bump_version!(gem_name, new_version)
      entry = find_entry(gem_name)
      raise ParseError, "gem not found: #{gem_name}" unless entry

      old_line = entry.raw_line
      new_entry = entry.with_version(new_version)
      new_line = new_entry.raw_line

      # Replace all occurrences of the old version for this gem
      lines = content.lines.dup
      old_version = entry.version

      lines.each_with_index do |line, idx|
        # Replace in spec lines: "    gem_name (version)"
        if line =~ /^\s{4}#{Regexp.escape(gem_name)}\s+\(#{Regexp.escape(old_version)}\)/
          lines[idx] = line.sub("(#{old_version})", "(#{new_version})")
        end

        # Replace in dependency lines: "      gem_name (= version)" or "(~> version)"
        # But only exact version constraints
        if line =~ /^\s{6}#{Regexp.escape(gem_name)}\s+\(=\s*#{Regexp.escape(old_version)}\)/
          lines[idx] = line.sub("(= #{old_version})", "(= #{new_version})")
        end
      end

      [ lines.join, old_line, new_line ]
    end

    private

    def parse_entries
      result = []
      in_gem_section = false
      in_specs = false

      content.lines.each_with_index do |line, idx|
        # Track section transitions
        if line.match?(GEM_SECTION_REGEX)
          in_gem_section = true
          in_specs = false
          next
        elsif line.match?(PLATFORM_SECTION_REGEX) || line.match?(PATH_SECTION_REGEX) || line.match?(GIT_SECTION_REGEX)
          in_gem_section = false
          in_specs = false
          next
        end

        if in_gem_section && line.match?(SPECS_SECTION_REGEX)
          in_specs = true
          next
        end

        # Parse gem entries in the specs section
        # Format: "    gem_name (version)"
        if in_specs && (match = line.match(GEM_LINE_REGEX))
          name = match[1]
          version = match[2]
          result << Entry.new(name, version, idx + 1, line)
        end

        # End of specs section (less indented line or new section)
        if in_specs && !line.strip.empty? && !line.start_with?("    ")
          in_gem_section = false
          in_specs = false
        end
      end

      result
    end
  end
end
