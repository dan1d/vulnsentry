require "rails_helper"

RSpec.describe "Admin::Advisories", type: :request do
  it "lists advisories with pagination" do
    create_list(:advisory, 3, source: "osv")
    sign_in_admin
    get "/admin/advisories"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Advisories")
  end

  it "shows an advisory" do
    advisory = create(:advisory, fingerprint: "osv:OSV-1", source: "osv")
    sign_in_admin
    get "/admin/advisories/#{advisory.id}"
    expect(response).to have_http_status(:success)
    expect(response.body).to include("osv:OSV-1")
  end
end
