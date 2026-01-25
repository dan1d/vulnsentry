class Admin::PullRequestsController < Admin::BaseController
  def index
    @pull_requests = PullRequest.order(created_at: :desc).limit(200)
  end

  def show
    @pull_request = PullRequest.find(params[:id])
  end
end
