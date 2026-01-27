class HomeController < ApplicationController
  def index
    per_page = (params[:per_page].presence || 10).to_i.clamp(5, 50)
    @pull_requests = PullRequest
      .includes(candidate_bump: :advisory, patch_bundle: :advisories)
      .order(created_at: :desc)
      .page(params[:page])
      .per(per_page)
  end
end
