module Ai
  class BundledGemsBumpAssistant
    class Error < StandardError; end

    def initialize(client: DeepseekClient.new)
      @client = client
    end

    def enabled?
      # ENV["ENABLE_DEEPSEEK_BUNDLED_GEMS_ASSIST"] == "true" && @client.enabled?
      true
    end

    # Returns { new_content:, changed_line_number:, old_line:, new_line: } or raises.
    def suggest_bump!(old_content:, gem_name:, target_version:)
      raise Error, "bundled gems AI assist disabled" unless enabled?

      system = <<~SYS
        You edit a plain text file called gems/bundled_gems.
        Return ONLY valid JSON. No markdown. No commentary.
        You MUST change exactly one existing line.
        Output schema:
        {"line_number":123,"old_line":"...","new_line":"..."}
      SYS

      user = <<~USER
        Find the line for gem "#{gem_name}" and update its version to "#{target_version}".
        Keep all other tokens (repo URL, revision, spacing) unchanged.
        The file format is:
        gem-name version repository-url [revision]
        Comment lines start with #.

        Return ONLY JSON per schema.

        FILE:
        #{old_content}
      USER

      json = @client.extract_json!(system: system, user: user)
      line_number = Integer(json.fetch("line_number"))
      old_line = json.fetch("old_line").to_s
      new_line = json.fetch("new_line").to_s

      lines = old_content.lines
      raise Error, "invalid line_number" unless line_number.between?(1, lines.length)

      actual_old = lines[line_number - 1]
      unless normalize_line(actual_old) == normalize_line(old_line)
        raise Error, "old_line mismatch"
      end

      unless new_line.include?(target_version) && new_line.start_with?("#{gem_name} ")
        raise Error, "new_line does not match gem/version"
      end

      newline = actual_old.end_with?("\n") ? "\n" : ""
      lines[line_number - 1] = new_line.delete_suffix("\n") + newline
      new_content = lines.join

      diff = RubyCore::DiffValidator.validate_one_line_change!(old_content: old_content, new_content: new_content)
      unless diff[:new_line].include?(target_version)
        raise Error, "diff did not apply target version"
      end

      {
        new_content: new_content,
        changed_line_number: diff[:changed_line_number],
        old_line: diff[:old_line],
        new_line: diff[:new_line]
      }
    rescue KeyError, ArgumentError => e
      raise Error, e.message
    end

    private
      def normalize_line(line)
        line.to_s.rstrip
      end
  end
end
