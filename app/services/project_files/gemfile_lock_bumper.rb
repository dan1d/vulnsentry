# frozen_string_literal: true

module ProjectFiles
  # Bumps gem versions in Gemfile.lock files.
  #
  # Unlike bundled_gems which is a simple text file with one gem per line,
  # Gemfile.lock has a more complex structure where:
  # - The gem version appears in the specs section
  # - Dependency constraints may also reference the version
  #
  # This bumper handles text-based replacement. For complex dependency graphs,
  # running `bundle update gem_name` is recommended.
  class GemfileLockBumper
    class BumpError < StandardError; end

    # Returns hash with:
    # - :new_content - The updated lockfile content
    # - :old_line - The original spec line
    # - :new_line - The updated spec line
    # - :diff - Diff info with changed_line_count
    def self.bump!(old_content:, gem_name:, target_version:)
      file = GemfileLockFile.new(old_content)
      new_content, old_line, new_line = file.bump_version!(gem_name, target_version)

      # Validate changes
      diff = validate_changes(old_content, new_content, gem_name, target_version)

      # Verify the target version appears in the new line
      unless new_line.include?(target_version)
        raise BumpError, "new line does not include target version: #{target_version}"
      end

      {
        new_content: new_content,
        old_line: old_line,
        new_line: new_line,
        diff: diff
      }
    end

    class << self
      private

      def validate_changes(old_content, new_content, gem_name, target_version)
        old_lines = old_content.lines
        new_lines = new_content.lines

        # Line count should remain the same for text-based replacement
        if old_lines.size != new_lines.size
          raise BumpError, "Line count changed unexpectedly (#{old_lines.size} -> #{new_lines.size})"
        end

        changed_indices = old_lines.each_index.select { |i| old_lines[i] != new_lines[i] }

        if changed_indices.empty?
          raise BumpError, "No changes detected for #{gem_name}"
        end

        # For Gemfile.lock, multiple lines may change:
        # - The spec line: "    gem_name (version)"
        # - Dependency constraints: "      other_gem (= version)"
        # All changed lines should relate to the target gem or version
        changed_indices.each do |idx|
          new_line = new_lines[idx]
          # The change should involve either the gem name or the new version
          unless new_line.include?(gem_name) || new_line.include?(target_version)
            # This could be a cascading dependency change - log but don't fail
            Rails.logger.warn(
              "GemfileLockBumper: Unexpected change at line #{idx + 1} " \
              "while bumping #{gem_name}: #{new_line.strip}"
            )
          end
        end

        {
          old_line: old_lines[changed_indices.first],
          new_line: new_lines[changed_indices.first],
          changed_line_count: changed_indices.size
        }
      end
    end
  end
end
