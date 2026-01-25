module Ai
  class MaintenanceBranchesCrossCheck
    class MismatchError < StandardError; end

    def initialize(client: DeepseekClient.new)
      @client = client
    end

    def enabled?
      @client.enabled?
    end

    # Returns array of RubyLang::MaintenanceBranches::Branch from LLM extraction.
    def extract_branches!(html)
      system = <<~SYS
        You extract structured data from HTML.
        Return ONLY valid JSON. No markdown. No commentary.
        Output schema: [{"series":"3.4","status":"normal|security|eol"}, ...]
      SYS

      user = <<~USER
        From this HTML, extract each Ruby series and its maintenance status (normal maintenance, security maintenance, eol).
        Normalize status:
        - "normal maintenance" => "normal"
        - "security maintenance" => "security"
        - "eol" => "eol"
        Return ONLY JSON per schema.

        HTML:
        #{html}
      USER

      json = @client.extract_json!(system: system, user: user)
      coerce(json)
    end

    # Raises MismatchError if LLM result does not match deterministic result.
    def verify_match!(deterministic:, llm:)
      d = deterministic.map { |b| [ b.series, b.status ] }.sort
      l = llm.map { |b| [ b.series, b.status ] }.sort

      return true if d == l

      raise MismatchError, "LLM cross-check mismatch"
    end

    private
      def coerce(json)
        unless json.is_a?(Array)
          raise DeepseekClient::Error, "expected JSON array"
        end

        json.map do |row|
          series = row.fetch("series")
          status = row.fetch("status")
          RubyLang::MaintenanceBranches::Branch.new(series.to_s, status.to_s)
        end
      end
  end
end
