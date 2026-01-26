require 'rails_helper'

RSpec.describe "Admin::CandidateBumps", type: :request do
  it "lists candidate bumps" do
    create(:candidate_bump)
    get "/admin/candidate_bumps", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "filters candidate bumps by state" do
    create(:candidate_bump, state: "ready_for_review", gem_name: "rexml")
    create(:candidate_bump, state: "approved", gem_name: "rake")

    get "/admin/candidate_bumps", params: { state: "approved" }, headers: admin_headers
    expect(response).to have_http_status(:success)
    expect(response.body).to include("approved")
    expect(response.body).to include("rake")
    expect(response.body).not_to include("rexml")
  end

  it "shows a candidate bump" do
    c = create(:candidate_bump)
    get "/admin/candidate_bumps/#{c.id}", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "approves a candidate bump" do
    c = create(:candidate_bump, state: "ready_for_review")
    BotConfig.delete_all
    create(:bot_config, require_human_approval: true, emergency_stop: false, allow_draft_pr: false)

    ActiveJob::Base.queue_adapter = :test
    expect do
      patch "/admin/candidate_bumps/#{c.id}", params: { event: "approve" }, headers: admin_headers
    end.to have_enqueued_job(CreatePullRequestJob)
    expect(response).to have_http_status(:redirect)
    expect(c.reload.state).to eq("approved")
  end
end
