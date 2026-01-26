require 'rails_helper'

RSpec.describe "Admin::BranchTargets", type: :request do
  it "lists branch targets" do
    create(:branch_target, name: "ruby_3_4", maintenance_status: "normal")
    sign_in_admin
    get "/admin/branch_targets"
    expect(response).to have_http_status(:success)
  end

  it "filters branch targets" do
    create(:branch_target, name: "ruby_3_4", maintenance_status: "normal", enabled: true)
    create(:branch_target, name: "ruby_3_2", maintenance_status: "security", enabled: false)

    sign_in_admin
    get "/admin/branch_targets", params: { enabled: "false" }
    expect(response).to have_http_status(:success)
    expect(response.body).to include("ruby_3_2")
    expect(response.body).not_to include("ruby_3_4")
  end

  it "edits a branch target" do
    bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal")
    sign_in_admin
    get "/admin/branch_targets/#{bt.id}/edit"
    expect(response).to have_http_status(:success)
  end

  it "updates a branch target" do
    bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal", enabled: true)
    sign_in_admin
    patch "/admin/branch_targets/#{bt.id}", params: { branch_target: { enabled: false } }
    expect(response).to have_http_status(:redirect)
    expect(bt.reload.enabled).to be(false)
  end
end
