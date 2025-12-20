# frozen_string_literal: true

module Auth
  # Authentication Controller
  #
  # Handles user signup, login, token refresh, and logout

  class AuthenticationController < ApplicationController
    skip_before_action :verify_authenticity_token

    # POST /auth/signup
    # Register a new user
    def signup
      user = User.new(signup_params)

      if user.save
        tokens = JwtService.generate_tokens(user)

        # Log audit event
        AuditLog.log_event(
          event_type: AuditLog::EventTypes::USER_LOGIN,
          actor_user: user,
          actor_ip: request.ip,
          metadata: { method: 'signup' }
        )

        render json: {
          success: true,
          data: {
            user: {
              id: user.id,
              email: user.email,
              role: user.role,
              tier: user.tier
            },
            tokens: tokens
          }
        }, status: :created
      else
        render json: {
          success: false,
          error: {
            code: 'VALIDATION_ERROR',
            message: 'User registration failed',
            details: user.errors.full_messages
          }
        }, status: :unprocessable_entity
      end
    end

    # POST /auth/login
    # Authenticate user and return tokens
    def login
      user = User.find_by(email: login_params[:email]&.downcase)

      if user&.authenticate(login_params[:password])
        tokens = JwtService.generate_tokens(user)

        # Log successful login
        AuditLog.log_event(
          event_type: AuditLog::EventTypes::USER_LOGIN,
          actor_user: user,
          actor_ip: request.ip
        )

        render json: {
          success: true,
          data: {
            user: {
              id: user.id,
              email: user.email,
              role: user.role,
              tier: user.tier
            },
            tokens: tokens
          }
        }
      else
        # Log failed login attempt
        AuditLog.log_event(
          event_type: AuditLog::EventTypes::USER_LOGIN_FAILED,
          actor_ip: request.ip,
          metadata: { email: login_params[:email] }
        )

        render json: {
          success: false,
          error: {
            code: 'INVALID_CREDENTIALS',
            message: 'Invalid email or password'
          }
        }, status: :unauthorized
      end
    end

    # POST /auth/refresh
    # Exchange refresh token for new access token
    def refresh
      refresh_token = params[:refresh_token]

      if refresh_token.blank?
        return render json: {
          success: false,
          error: {
            code: 'MISSING_REFRESH_TOKEN',
            message: 'Refresh token is required'
          }
        }, status: :bad_request
      end

      begin
        tokens = JwtService.refresh_tokens(refresh_token)

        render json: {
          success: true,
          data: { tokens: tokens }
        }
      rescue JwtService::TokenExpiredError
        render json: {
          success: false,
          error: {
            code: 'REFRESH_TOKEN_EXPIRED',
            message: 'Refresh token has expired. Please login again.'
          }
        }, status: :unauthorized
      rescue JwtService::TokenInvalidError, JwtService::TokenRevokedError
        render json: {
          success: false,
          error: {
            code: 'INVALID_REFRESH_TOKEN',
            message: 'Invalid or revoked refresh token'
          }
        }, status: :unauthorized
      end
    end

    # POST /auth/logout
    # Revoke current access token (requires authentication)
    def logout
      # Extract token from header
      token = JwtService.extract_from_header(request.headers['Authorization'])

      if token.present?
        JwtService.revoke_token(token)

        # If using API key, could revoke it here as well
        # But typically API keys are long-lived and manually managed

        render json: {
          success: true,
          message: 'Successfully logged out'
        }
      else
        render json: {
          success: false,
          error: {
            code: 'NO_TOKEN',
            message: 'No token provided'
          }
        }, status: :bad_request
      end
    end

    private

    def signup_params
      params.require(:user).permit(:email, :password, :password_confirmation)
    end

    def login_params
      params.require(:user).permit(:email, :password)
    end
  end
end
