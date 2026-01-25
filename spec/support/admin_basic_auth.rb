module AdminBasicAuth
  def admin_headers(user: ENV.fetch("ADMIN_USER", "admin"), password: ENV.fetch("ADMIN_PASSWORD", "password"))
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials(user, password)
    { "HTTP_AUTHORIZATION" => credentials }
  end
end

RSpec.configure do |config|
  config.include AdminBasicAuth, type: :request
end

