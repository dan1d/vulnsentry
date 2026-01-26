require 'rails_helper'

RSpec.describe "Admin::Settings", type: :request do
  it "shows settings" do
    sign_in_admin
    get "/admin/settings"
    expect(response).to have_http_status(:success)
  end

  it "edits settings" do
    sign_in_admin
    get "/admin/settings/edit"
    expect(response).to have_http_status(:success)
  end

  it "updates settings" do
    sign_in_admin
    patch "/admin/settings", params: { bot_config: { global_daily_cap: 2 } }
    expect(response).to have_http_status(:redirect)
    expect(BotConfig.instance.global_daily_cap).to eq(2)
  end
end
