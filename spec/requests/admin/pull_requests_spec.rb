require 'rails_helper'

RSpec.describe "Admin::PullRequests", type: :request do
  it "lists pull requests" do
    cb = create(:candidate_bump)
    create(:pull_request, candidate_bump: cb)
    sign_in_admin
    get "/admin/pull_requests"
    expect(response).to have_http_status(:success)
  end

  it "filters pull requests by status" do
    cb1 = create(:candidate_bump, base_branch: "master")
    cb2 = create(:candidate_bump, base_branch: "ruby_3_4")
    create(:pull_request, candidate_bump: cb1, status: "open")
    create(:pull_request, candidate_bump: cb2, status: "closed")

    sign_in_admin
    get "/admin/pull_requests", params: { status: "closed" }
    expect(response).to have_http_status(:success)
    expect(response.body).to include("closed")
    expect(response.body).to include("ruby_3_4")
    expect(response.body).not_to include("master")
  end

  it "shows a pull request" do
    cb = create(:candidate_bump)
    pr = create(:pull_request, candidate_bump: cb)
    sign_in_admin
    get "/admin/pull_requests/#{pr.id}"
    expect(response).to have_http_status(:success)
  end
end
