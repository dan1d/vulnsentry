# frozen_string_literal: true

module Github
  # Fetches branches from a GitHub repository.
  # Used for discovering maintenance branches for projects like Rails.
  class BranchesFetcher
    class FetchError < StandardError; end

    # Branch info returned from GitHub API
    BranchInfo = Data.define(:name, :protected, :commit_sha)

    def initialize(gh: GhCli.new)
      @gh = gh
    end

    # Fetch all branches from a repository
    # @param repo [String] Repository in owner/repo format
    # @return [Array<BranchInfo>]
    def fetch_all(repo:)
      result = @gh.json!(
        "api",
        "repos/#{repo}/branches",
        "--paginate",
        "--jq", ".[].name"
      )

      # gh returns newline-separated names with --jq
      branch_names = result.strip.split("\n").reject(&:blank?)

      branch_names.map do |name|
        BranchInfo.new(name: name, protected: false, commit_sha: nil)
      end
    rescue Github::GhCli::CommandError => e
      raise FetchError, "Failed to fetch branches for #{repo}: #{e.message}"
    end

    # Fetch branches matching a pattern (e.g., stable branches)
    # @param repo [String] Repository in owner/repo format
    # @param pattern [Regexp] Pattern to match branch names
    # @return [Array<BranchInfo>]
    def fetch_matching(repo:, pattern:)
      fetch_all(repo: repo).select { |b| b.name.match?(pattern) }
    end

    # Fetch Rails-style maintenance branches (X-Y-stable format)
    # @param repo [String] Repository in owner/repo format
    # @return [Array<BranchInfo>]
    def fetch_rails_stable_branches(repo:)
      # Rails uses X-Y-stable format (e.g., 7-1-stable, 7-0-stable)
      pattern = /^\d+-\d+-stable$/
      branches = fetch_matching(repo: repo, pattern: pattern)

      # Also include main branch
      all_branches = fetch_all(repo: repo)
      main_branch = all_branches.find { |b| b.name == "main" || b.name == "master" }

      result = branches.sort_by { |b| version_sort_key(b.name) }.reverse
      result.unshift(main_branch) if main_branch
      result.compact
    end

    private

    # Convert branch name to sortable version array
    # "7-1-stable" => [7, 1]
    def version_sort_key(name)
      match = name.match(/^(\d+)-(\d+)-stable$/)
      return [ 0, 0 ] unless match

      [ match[1].to_i, match[2].to_i ]
    end
  end
end
