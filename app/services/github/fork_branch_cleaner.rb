module Github
  class ForkBranchCleaner
    def initialize(gh: GhCli.new)
      @gh = gh
    end

    # Deletes refs/heads/<branch> in <repo> (e.g. "dan1d/ruby").
    # Returns true if deleted, false if not found.
    def delete_branch(repo:, branch:)
      path = "/repos/#{repo}/git/refs/heads/#{branch}"
      @gh.run!("api", "--silent", "--method", "DELETE", path)
      true
    rescue Github::GhCli::CommandError => e
      return false if e.stderr.to_s.include?("Not Found")
      raise
    end
  end
end
