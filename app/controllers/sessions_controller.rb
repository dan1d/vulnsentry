class SessionsController < ApplicationController
  def new
  end

  def create
    user = AdminUser.find_by(username: params[:username].to_s)

    if user&.authenticate(params[:password].to_s)
      session[:admin_user_id] = user.id
      redirect_to admin_root_path, notice: "Signed in"
    else
      flash.now[:alert] = "Invalid username or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out"
  end
end
