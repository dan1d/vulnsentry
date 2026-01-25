class Admin::BaseController < ApplicationController
  before_action :http_basic_authenticate!

  private
    def http_basic_authenticate!
      user = ENV.fetch("ADMIN_USER", nil)
      password = ENV.fetch("ADMIN_PASSWORD", nil)

      # If not configured, lock it down rather than accidentally exposing.
      unless user.present? && password.present?
        head :not_found
        return
      end

      authenticate_or_request_with_http_basic("Admin") do |u, p|
        ActiveSupport::SecurityUtils.secure_compare(u, user) &&
          ActiveSupport::SecurityUtils.secure_compare(p, password)
      end
    end
end

