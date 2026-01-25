require 'rails_helper'

RSpec.describe "Admin::BranchTargets", type: :request do
  it "lists branch targets" do
    create(:branch_target, name: "ruby_3_4", maintenance_status: "normal")
    get "/admin/branch_targets", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "edits a branch target" do
    bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal")
    get "/admin/branch_targets/#{bt.id}/edit", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "updates a branch target" do
    bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal", enabled: true)
    patch "/admin/branch_targets/#{bt.id}", params: { branch_target: { enabled: false } }, headers: admin_headers
    expect(response).to have_http_status(:redirect)
    expect(bt.reload.enabled).to be(false)
  end

end
