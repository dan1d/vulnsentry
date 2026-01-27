require "net/http"
require "uri"
require "nokogiri"

module RubyLang
  class MaintenanceBranches
    Branch = Data.define(:series, :status)

    class FetchError < StandardError; end
    class ParseError < StandardError; end

    URL = "https://www.ruby-lang.org/en/downloads/branches/"

    def initialize(http: Net::HTTP)
      @http = http
    end

    # Returns array of Branch for non-EOL branches.
    # status is one of: "normal", "security"
    def fetch_supported
      html = fetch_html
      parse_supported_html(html)
    end

    def fetch_html
      fetch(URL)
    end

    def parse_supported_html(html)
      parse_all_html(html).reject { |b| b.status == "eol" }
    end

    # Returns array of Branch including EOL branches.
    # status is one of: "normal", "security", "eol"
    def parse_all_html(html)
      doc = Nokogiri::HTML(html)

      branches = []

      doc.css("h3").each do |h3|
        text = h3.text.to_s.strip
        next unless (m = text.match(/\ARuby\s+(\d+\.\d+(?:\.\d+)?)\z/i))

        series = m[1]
        status_text = find_status_text(h3)
        status = normalize_status(status_text)
        branches << Branch.new(series, status)
      end

      branches = branches.uniq { |b| b.series }
      sanity_check!(branches)

      branches
    end

    private
      def fetch(url)
        uri = URI.parse(url)
        response = @http.get_response(uri)
        raise FetchError, "ruby-lang request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        response.body
      end

      def find_status_text(h3)
        node = h3
        while (node = node.next_sibling)
          next if node.text? && node.text.to_s.strip.empty?
          break if node.element? && node.name == "h3"

          text = node.text.to_s
          return text if text.match?(/status:/i)
        end

        raise ParseError, "status not found for #{h3.text.inspect}"
      end

      def normalize_status(text)
        # ruby-lang HTML often uses `<br>` without newlines; Nokogiri will then
        # produce a single text line like:
        #   "status: eolrelease date: ...normal maintenance until: ..."
        # In that case, checking for "normal maintenance" first would misclassify
        # EOL/security branches. Extract just the status field and prioritize
        # security/eol over normal.
        raw = text.to_s.downcase
        status_value = raw[/status:\s*(.+?)(?:release date:|normal maintenance until:|eol:|\z)/im, 1]&.strip
        raise ParseError, "unrecognized status (missing status:): #{text.inspect}" if status_value.blank?

        return "security" if status_value.include?("security maintenance")
        return "eol" if status_value.include?("eol") || status_value.include?("end-of-life") || status_value.include?("end of life")
        return "normal" if status_value.include?("normal maintenance")

        raise ParseError, "unrecognized status: #{status_value.inspect}"
      end

      def sanity_check!(branches)
        raise ParseError, "no branches found" if branches.empty?

        unless branches.any? { |b| b.series.match?(/\A\d+\.\d+(?:\.\d+)?\z/) }
          raise ParseError, "no valid series entries found"
        end

        unless branches.any? { |b| b.status == "normal" || b.status == "security" }
          raise ParseError, "no supported statuses found"
        end
      end
  end
end
