require 'rails_helper'

RSpec.describe "Admin::CandidateBumps", type: :request do
  it "lists candidate bumps" do
    create(:candidate_bump)
    sign_in_admin
    get "/admin/candidate_bumps"
    expect(response).to have_http_status(:success)
  end

  it "filters candidate bumps by state" do
    create(:candidate_bump, state: "ready_for_review", gem_name: "rexml")
    create(:candidate_bump, state: "approved", gem_name: "rake")

    sign_in_admin
    get "/admin/candidate_bumps", params: { state: "approved" }
    expect(response).to have_http_status(:success)
    expect(response.body).to include("approved")
    expect(response.body).to include("rake")
    expect(response.body).not_to include("rexml")
  end

  it "shows a candidate bump" do
    c = create(:candidate_bump)
    sign_in_admin
    get "/admin/candidate_bumps/#{c.id}"
    expect(response).to have_http_status(:success)
  end

  it "approves a candidate bump" do
    c = create(:candidate_bump, state: "ready_for_review")
    admin = sign_in_admin
    patch "/admin/candidate_bumps/#{c.id}", params: { event: "approve" }
    expect(response).to have_http_status(:redirect)
    expect(c.reload.state).to eq("approved")
    expect(c.reload.approved_by).to eq(admin.username)
  end

  it "enqueues PR creation only when explicitly requested" do
    BotConfig.delete_all
    create(:bot_config, emergency_stop: false)

    c = create(:candidate_bump, state: "approved")

    ActiveJob::Base.queue_adapter = :test
    sign_in_admin
    expect do
      patch "/admin/candidate_bumps/#{c.id}", params: { event: "create_pr" }
    end.to have_enqueued_job(CreatePullRequestJob)
  end
end
