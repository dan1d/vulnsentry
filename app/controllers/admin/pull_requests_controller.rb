class Admin::PullRequestsController < Admin::BaseController
  def index
    query = AdminQueries::PullRequestsQuery.new.call(params)
    @pagy, @pull_requests = pagy(query)
  end

  def show
    @pull_request = PullRequest.find(params[:id])
  end
end
