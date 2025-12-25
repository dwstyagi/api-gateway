# frozen_string_literal: true

# Registrations Controller
#
# Handles user registration for the web UI
class RegistrationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]

  def new
    # Show signup page
    redirect_to dashboard_path if current_user && current_user.admin?
    redirect_to account_path if current_user && !current_user.admin?
  end

  def create
    user = User.new(registration_params)

    if user.save
      # Create session automatically after signup
      session[:user_id] = user.id
      session[:auth_method] = 'session'

      # Log the registration
      AuditLog.create(
        event_type: 'web.signup',
        user_id: user.id,
        actor_ip: request.ip,
        metadata: { email: user.email, tier: user.tier }
      )

      # Redirect based on role
      if user.admin?
        redirect_to dashboard_path, notice: 'Welcome! Your account has been created.'
      else
        redirect_to account_path, notice: 'Welcome! Your account has been created.'
      end
    else
      flash.now[:alert] = user.errors.full_messages.join(', ')
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.permit(:email, :password, :password_confirmation, :tier).tap do |p|
      # Default to 'user' role and 'free' tier if not specified
      p[:role] ||= 'user'
      p[:tier] ||= 'free'
    end
  end
end
