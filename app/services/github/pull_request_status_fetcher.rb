module Github
  class PullRequestStatusFetcher
    def initialize(gh: GhCli.new)
      @gh = gh
    end

    # Returns hash with :status ("open"/"closed"/"merged"), and timestamps.
    def fetch(upstream_repo:, pr_number:)
      data = @gh.json!("api", "--silent", "--method", "GET", "/repos/#{upstream_repo}/pulls/#{pr_number}")

      state = data.fetch("state") # "open" / "closed"
      merged_at = data["merged_at"]
      closed_at = data["closed_at"]

      status =
        if merged_at
          "merged"
        elsif state == "closed"
          "closed"
        else
          "open"
        end

      {
        status: status,
        opened_at: data["created_at"],
        merged_at: merged_at,
        closed_at: closed_at
      }
    end
  end
end

