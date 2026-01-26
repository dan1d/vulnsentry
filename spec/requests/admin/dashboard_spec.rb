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
end
