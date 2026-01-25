require 'rails_helper'

RSpec.describe "Admin::CandidateBumps", type: :request do
  it "lists candidate bumps" do
    create(:candidate_bump)
    get "/admin/candidate_bumps", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "shows a candidate bump" do
    c = create(:candidate_bump)
    get "/admin/candidate_bumps/#{c.id}", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "approves a candidate bump" do
    c = create(:candidate_bump, state: "ready_for_review")
    patch "/admin/candidate_bumps/#{c.id}", params: { event: "approve" }, headers: admin_headers
    expect(response).to have_http_status(:redirect)
    expect(c.reload.state).to eq("approved")
  end
end
