class HomeController < ApplicationController
  def index
    @merged_prs = PullRequest
      .includes(candidate_bump: :advisory)
      .where(status: "merged")
      .order(merged_at: :desc, created_at: :desc)
      .limit(50)
  end
end
