class Admin::PullRequestsController < Admin::BaseController
  def index
    per_page = (params[:per_page].presence || 20).to_i.clamp(10, 100)
    query = AdminQueries::PullRequestsQuery.new.call(params)
    @pull_requests = query.page(params[:page]).per(per_page)
  end

  def show
    @pull_request = PullRequest.find(params[:id])
  end
end
