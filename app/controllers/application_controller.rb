class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :admin_signed_in?
  helper_method :current_admin_user

  private
    def current_admin_user
      return nil if session[:admin_user_id].blank?

      @current_admin_user ||= AdminUser.find_by(id: session[:admin_user_id])
    end

    def admin_signed_in?
      current_admin_user.present?
    end

    def require_admin!
      return if admin_signed_in?

      redirect_to sign_in_path, alert: "Please sign in"
    end
end
