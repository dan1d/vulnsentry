require 'rails_helper'

RSpec.describe "Admin::Dashboards", type: :request do
  it "requires basic auth" do
    get "/admin"
    expect(response).to have_http_status(:unauthorized).or have_http_status(:not_found)
  end

  it "renders dashboard when authenticated" do
    get "/admin", headers: admin_headers
    expect(response).to have_http_status(:success)
  end
end
