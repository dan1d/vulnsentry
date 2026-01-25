module RubyCore
  class BundledGemsBumper
    # Returns struct-like hash with:
    # - :new_content
    # - :diff (one-line diff info)
    def self.bump!(old_content:, gem_name:, target_version:)
      file = BundledGemsFile.new(old_content)
      new_content, old_line, new_line = file.bump_version!(gem_name, target_version)

      diff = DiffValidator.validate_one_line_change!(old_content: old_content, new_content: new_content)

      # Extra assertion: version token actually changed to target_version.
      unless diff[:new_line].include?(target_version)
        raise DiffValidator::ValidationError, "new line does not include target version"
      end

      {
        new_content: new_content,
        old_line: old_line,
        new_line: new_line,
        diff: diff
      }
    end
  end
end

