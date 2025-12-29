# frozen_string_literal: true

# Sessions Controller
#
# Handles web-based user authentication with sessions
# Provides login/logout functionality for the web UI
class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy]

  def new
    # Show login page
    redirect_to dashboard_path if current_user && current_user.admin?
    redirect_to consumer_dashboard_path if current_user && !current_user.admin?
  end

  def create
    # Authenticate user
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      # Create session
      session[:user_id] = user.id
      session[:auth_method] = 'session'

      # Log the login
      AuditLog.create(
        timestamp: Time.current,
        event_type: 'web.login',
        actor_user_id: user.id,
        actor_ip: request.ip,
        metadata: { email: user.email, method: 'password' }
      )

      # Redirect based on role
      if user.admin?
        redirect_to dashboard_path, notice: 'Welcome back, Admin!'
      else
        redirect_to consumer_dashboard_path, notice: 'Welcome to your Developer Portal!'
      end
    else
      # Authentication failed
      flash.now[:alert] = 'Invalid email or password'
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    # Logout user
    user_id = session[:user_id]

    # Log the logout
    if user_id
      AuditLog.create(
        timestamp: Time.current,
        event_type: 'web.logout',
        actor_user_id: user_id,
        actor_ip: request.ip,
        metadata: { method: 'manual' }
      )
    end

    # Clear session
    session.delete(:user_id)
    session.delete(:auth_method)
    reset_session

    redirect_to login_path, notice: 'You have been logged out'
  end
end
