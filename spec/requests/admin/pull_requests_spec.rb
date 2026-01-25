require 'rails_helper'

RSpec.describe "Admin::PullRequests", type: :request do
  it "lists pull requests" do
    cb = create(:candidate_bump)
    create(:pull_request, candidate_bump: cb)
    get "/admin/pull_requests", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "shows a pull request" do
    cb = create(:candidate_bump)
    pr = create(:pull_request, candidate_bump: cb)
    get "/admin/pull_requests/#{pr.id}", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

end
