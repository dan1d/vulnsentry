require 'rails_helper'

RSpec.describe "Admin::Settings", type: :request do
  it "shows settings" do
    get "/admin/settings", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "edits settings" do
    get "/admin/settings/edit", headers: admin_headers
    expect(response).to have_http_status(:success)
  end

  it "updates settings" do
    patch "/admin/settings", params: { bot_config: { global_daily_cap: 2 } }, headers: admin_headers
    expect(response).to have_http_status(:redirect)
    expect(BotConfig.instance.global_daily_cap).to eq(2)
  end

end
