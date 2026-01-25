require "net/http"
require "uri"

module RubyLang
  class MaintenanceBranches
    Branch = Data.define(:series, :status)

    class FetchError < StandardError; end

    URL = "https://www.ruby-lang.org/en/downloads/branches/"

    def initialize(http: Net::HTTP)
      @http = http
    end

    # Returns array of Branch for non-EOL branches.
    # status is one of: "normal", "security"
    def fetch_supported
      html = fetch(URL)
      parse_supported(html)
    end

    def parse_supported(html)
      # The page contains repeated blocks like:
      # ### Ruby 3.4
      # status: normal maintenance
      matches = html.scan(/Ruby\s+(\d+\.\d+).*?status:\s*(normal maintenance|security maintenance|eol)/mi)

      branches = matches.map do |series, status|
        normalized =
          case status.downcase
          when "normal maintenance" then "normal"
          when "security maintenance" then "security"
          else "eol"
          end

        Branch.new(series, normalized)
      end

      branches
        .uniq { |b| b.series }
        .reject { |b| b.status == "eol" }
    end

    private
      def fetch(url)
        uri = URI.parse(url)
        response = @http.get_response(uri)
        raise FetchError, "ruby-lang request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        response.body
      end
  end
end

