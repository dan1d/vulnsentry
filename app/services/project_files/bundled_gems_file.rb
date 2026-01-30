# frozen_string_literal: true

module ProjectFiles
  # Parser for Ruby's bundled_gems file format.
  # Format: gem-name version repository-url [revision]
  #
  # Example:
  #   rexml 3.4.4 https://github.com/ruby/rexml
  #   json 2.9.1 https://github.com/ruby/json 7eba852
  class BundledGemsFile < Base
    # Extended Entry with repo_url and revision
    Entry = Data.define(:name, :version, :repo_url, :revision, :line_number, :raw_line) do
      def with_version(new_version)
        newline = raw_line.end_with?("\n") ? "\n" : ""
        line_body = raw_line.delete_suffix("\n")
        updated_body = line_body.sub(
          /\A(?<name>\S+)(?<ws1>\s+)(?<version>\S+)(?<rest>.*)\z/,
          "\\k<name>\\k<ws1>#{new_version}\\k<rest>"
        )
        updated_line = "#{updated_body}#{newline}"
        self.class.new(name, new_version, repo_url, revision, line_number, updated_line)
      end
    end

    def entries
      @entries ||= parse_entries
    end

    def find_entry(gem_name)
      entries.find { |e| e.name == gem_name }
    end

    # Returns [new_content, old_line, new_line] or raises if gem not found.
    def bump_version!(gem_name, new_version)
      entry = find_entry(gem_name)
      raise ParseError, "gem not found: #{gem_name}" unless entry

      old_line = entry.raw_line
      new_entry = entry.with_version(new_version)
      new_line = new_entry.raw_line

      lines = content.lines
      lines[entry.line_number - 1] = new_line
      [ lines.join, old_line, new_line ]
    end

    private

    def parse_entries
      result = []
      content.lines.each_with_index do |line, idx|
        next if line.strip.empty?
        next if line.lstrip.start_with?("#")

        # Format:
        # gem-name version repository-url [revision]
        parts = line.strip.split(/\s+/)
        raise ParseError, "invalid bundled_gems line #{idx + 1}: #{line.inspect}" if parts.length < 3

        name = parts[0]
        version = parts[1]
        repo_url = parts[2]
        revision = parts[3]

        result << Entry.new(name, version, repo_url, revision, idx + 1, line)
      end
      result
    end
  end
end

# Backwards compatibility alias
module RubyCore
  BundledGemsFile = ProjectFiles::BundledGemsFile
end
