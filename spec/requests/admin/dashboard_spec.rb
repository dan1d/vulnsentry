require 'rails_helper'

RSpec.describe "Admin::Dashboards", type: :request do
  it "redirects to sign in when not authenticated" do
    get "/admin"
    expect(response).to redirect_to("/sign_in")
  end

  it "renders dashboard when authenticated" do
    sign_in_admin
    get "/admin"
    expect(response).to have_http_status(:success)
  end

  it "counts only supported (enabled + non-EOL) branch targets" do
    sign_in_admin

    create(:branch_target, name: "ruby_3_4", enabled: true, maintenance_status: "normal")
    create(:branch_target, name: "ruby_3_3", enabled: true, maintenance_status: "security")
    create(:branch_target, name: "ruby_2_7", enabled: true, maintenance_status: "eol")
    create(:branch_target, name: "ruby_3_2", enabled: false, maintenance_status: "normal")

    get "/admin"
    expect(response).to have_http_status(:success)
    expect(response.body).to include(">2<") # stat card value is rendered as a link
  end
end
