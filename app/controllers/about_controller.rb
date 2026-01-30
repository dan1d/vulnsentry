class AboutController < ApplicationController
  def index
    # Optional: Fetch stats for hero section
    @total_prs = PullRequest.count
    @open_prs = PullRequest.where(status: "open").count
    @merged_prs = PullRequest.where(status: "merged").count
    @total_advisories = Advisory.count
    @branch_targets = BranchTarget.where(enabled: true).count
    @patch_bundles = PatchBundle.count
    @llm_assisted_bundles = PatchBundle.where(resolution_source: "llm").count
  end
end
