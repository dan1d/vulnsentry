module RubyCore
  class DiffValidator
    class ValidationError < StandardError; end

    # Validates the edit is a 1-line change in the same-length file.
    #
    # Returns a hash with :changed_line_number, :old_line, :new_line.
    def self.validate_one_line_change!(old_content:, new_content:)
      old_lines = old_content.lines
      new_lines = new_content.lines

      raise ValidationError, "line count changed" unless old_lines.length == new_lines.length

      changed = []
      old_lines.each_with_index do |old_line, idx|
        new_line = new_lines[idx]
        next if old_line == new_line
        changed << [idx + 1, old_line, new_line]
      end

      raise ValidationError, "no changes detected" if changed.empty?
      raise ValidationError, "more than one line changed (#{changed.length})" if changed.length != 1

      line_number, old_line, new_line = changed.first
      { changed_line_number: line_number, old_line: old_line, new_line: new_line }
    end
  end
end

