class HomeController < ApplicationController
  def index
    per_page = (params[:per_page].presence || 10).to_i.clamp(5, 50)
    @merged_prs = PullRequest
      .includes(candidate_bump: :advisory)
      .where(status: "merged")
      .order(merged_at: :desc, created_at: :desc)
      .page(params[:page])
      .per(per_page)
  end
end
