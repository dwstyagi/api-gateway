# frozen_string_literal: true

module ApplicationCable
  # WebSocket Connection
  #
  # Authenticates WebSocket connections using:
  # 1. Session cookies (for web UI users)
  # 2. JWT tokens (for API clients)
  #
  # Usage:
  #   Web UI: Automatically authenticated via session cookie
  #   API: ws://host/cable?token=<jwt_token>
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      logger.info "WebSocket connected: User #{current_user.id} (#{current_user.email})"
    end

    def disconnect
      logger.info "WebSocket disconnected: User #{current_user&.id}"
    end

    private

    # Find and authenticate the user
    def find_verified_user
      # Try session-based authentication first (web UI)
      if session_user = find_user_from_session
        return session_user
      end

      # Try JWT token from query params (API clients)
      if token_user = find_user_from_token
        return token_user
      end

      # No valid authentication found
      reject_unauthorized_connection
    end

    # Authenticate via session cookie
    def find_user_from_session
      # Access session from cookies
      if session_id = cookies.encrypted[:_api_gateway_session]
        # Rails session handling
        session_data = Rails.application.config.session_store.new({}).send(:load_session_from_sid, session_id)
        user_id = session_data&.dig('user_id')

        if user_id
          user = User.find_by(id: user_id)
          return user if user
        end
      end

      # Alternative: Try to get user_id from request.session
      if request.session[:user_id]
        user = User.find_by(id: request.session[:user_id])
        return user if user
      end

      nil
    rescue StandardError => e
      logger.error "Session auth error: #{e.message}"
      nil
    end

    # Authenticate via JWT token
    def find_user_from_token
      # Get token from query params: ws://host/cable?token=<jwt>
      token = request.params[:token]
      return nil unless token

      # Decode JWT
      payload = JwtService.decode(token, token_type: 'access')
      user = User.find_by(id: payload['sub'])

      return user if user

      nil
    rescue JwtService::TokenExpiredError
      logger.warn 'WebSocket auth failed: Token expired'
      nil
    rescue JwtService::TokenInvalidError => e
      logger.warn "WebSocket auth failed: #{e.message}"
      nil
    rescue StandardError => e
      logger.error "Token auth error: #{e.message}"
      nil
    end

    # Access cookies for session authentication
    def cookies
      @cookies ||= ActionDispatch::Request.new(env).cookie_jar
    end

    # Access session for session authentication
    def session
      @session ||= request.session
    end
  end
end
