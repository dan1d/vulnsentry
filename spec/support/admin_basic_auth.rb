module AdminSessionAuth
  def sign_in_admin(user: nil, password: "password")
    user ||= create(:admin_user, password: password, password_confirmation: password)
    post "/sign_in", params: { username: user.username, password: password }
    user
  end
end

RSpec.configure do |config|
  config.include AdminSessionAuth, type: :request
end
