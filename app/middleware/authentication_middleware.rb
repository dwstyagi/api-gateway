# frozen_string_literal: true

# Authentication Middleware for API Gateway
#
# This middleware intercepts all requests and performs authentication using either:
# 1. JWT (JSON Web Token) from Authorization header
# 2. API Key from X-API-Key header
#
# On successful authentication:
# - Sets env['current_user'] - The authenticated user object
# - Sets env['auth_method'] - 'jwt' or 'api_key'
# - Sets env['api_key'] - The API key object (if using API key auth)
#
# On failed authentication:
# - Returns 401 Unauthorized with error details
# - Logs the authentication failure

class AuthenticationMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    # Skip authentication for public routes
    return @app.call(env) if public_route?(request.path)

    # Try to authenticate the request
    auth_result = authenticate(request)

    if auth_result[:success]
      # Set authentication context for downstream middleware/controllers
      env['current_user'] = auth_result[:user]
      env['auth_method'] = auth_result[:method]
      env['api_key'] = auth_result[:api_key] if auth_result[:api_key]

      # Continue to next middleware/controller
      @app.call(env)
    else
      # Authentication failed - return 401
      unauthorized_response(auth_result[:error], auth_result[:details])
    end
  rescue StandardError => e
    # Unexpected error during authentication
    Rails.logger.error("Authentication error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    internal_error_response
  end

  private

  # Attempt to authenticate request using JWT or API Key
  #
  # @param request [ActionDispatch::Request]
  # @return [Hash] Authentication result
  def authenticate(request)
    # Try JWT authentication first (Authorization header)
    jwt_token = JwtService.extract_from_header(request.headers['Authorization'])
    if jwt_token.present?
      return authenticate_jwt(jwt_token, request)
    end

    # Try API Key authentication (X-API-Key header)
    api_key = request.headers['X-API-Key']
    if api_key.present?
      return authenticate_api_key(api_key, request)
    end

    # No authentication credentials provided
    AutoBlockerService.record_auth_failure(request.ip)
    {
      success: false,
      error: 'MISSING_CREDENTIALS',
      details: 'No authentication credentials provided. Include Authorization header with JWT or X-API-Key header.'
    }
  end

  # Authenticate using JWT
  #
  # @param token [String] JWT token
  # @param request [ActionDispatch::Request]
  # @return [Hash] Authentication result
  def authenticate_jwt(token, request)
    payload = JwtService.decode(token, token_type: 'access')
    user = User.find_by(id: payload['sub'])

    unless user
      AutoBlockerService.record_auth_failure(request.ip)
      return {
        success: false,
        error: 'USER_NOT_FOUND',
        details: 'User associated with token not found'
      }
    end

    # Log successful authentication
    log_auth_success('jwt', user, request)

    # Clear violations on successful auth
    AutoBlockerService.clear_violations(request.ip)

    {
      success: true,
      user: user,
      method: 'jwt'
    }

  rescue JwtService::TokenExpiredError
    log_auth_failure('jwt', 'token_expired', request)
    AutoBlockerService.record_auth_failure(request.ip)
    {
      success: false,
      error: 'TOKEN_EXPIRED',
      details: 'Your session has expired. Please login again.'
    }

  rescue JwtService::TokenVersionMismatchError
    log_auth_failure('jwt', 'token_revoked', request)
    {
      success: false,
      error: 'TOKEN_REVOKED',
      details: 'Your session has been invalidated. Please login again.'
    }

  rescue JwtService::TokenRevokedError
    log_auth_failure('jwt', 'token_blacklisted', request)
    {
      success: false,
      error: 'TOKEN_REVOKED',
      details: 'This token has been revoked.'
    }

  rescue JwtService::TokenInvalidError => e
    log_auth_failure('jwt', 'invalid_token', request)
    AutoBlockerService.record_invalid_jwt(request.ip)
    {
      success: false,
      error: 'INVALID_TOKEN',
      details: e.message
    }
  end

  # Authenticate using API Key
  #
  # @param key [String] API key
  # @param request [ActionDispatch::Request]
  # @return [Hash] Authentication result
  def authenticate_api_key(key, request)
    api_key = ApiKey.authenticate(key)

    unless api_key
      log_auth_failure('api_key', 'invalid_key', request)
      AutoBlockerService.record_invalid_api_key(request.ip)
      return {
        success: false,
        error: 'INVALID_API_KEY',
        details: 'The provided API key is invalid or has been revoked.'
      }
    end

    # Check if key is expired
    if api_key.expired?
      log_auth_failure('api_key', 'key_expired', request)
      return {
        success: false,
        error: 'API_KEY_EXPIRED',
        details: 'This API key has expired.'
      }
    end

    # Log successful authentication
    log_auth_success('api_key', api_key.user, request)

    # Clear violations on successful auth
    AutoBlockerService.clear_violations(request.ip)

    {
      success: true,
      user: api_key.user,
      method: 'api_key',
      api_key: api_key
    }

  rescue StandardError => e
    Rails.logger.error("API Key authentication error: #{e.message}")
    {
      success: false,
      error: 'AUTHENTICATION_ERROR',
      details: 'An error occurred during authentication.'
    }
  end

  # Check if route is public (doesn't require authentication)
  #
  # @param path [String] Request path
  # @return [Boolean]
  def public_route?(path)
    return true if path == '/'

    public_routes = [
      '/health',     # Health check endpoints (includes /health/detailed)
      '/auth/login',
      '/auth/signup',
      '/auth/refresh',
      '/login',      # Web login page
      '/signup',     # Web signup page
      '/logout',     # Web logout
      '/dashboard',  # Web admin dashboard (has its own auth check)
      '/admin',      # Admin Safety Console (has its own auth check via require_admin)
      '/account',    # Web user dashboard (has its own auth check)
      '/developer'   # Consumer/Developer portal (has its own auth check)
    ]

    public_routes.any? { |route| path.start_with?(route) }
  end

  # Log successful authentication
  #
  # @param method [String] Auth method ('jwt' or 'api_key')
  # @param user [User]
  # @param request [ActionDispatch::Request]
  def log_auth_success(method, user, request)
    Rails.logger.info({
      event: 'authentication_success',
      method: method,
      user_id: user.id,
      ip: request.ip,
      path: request.path,
      user_agent: request.user_agent
    }.to_json)
  end

  # Log failed authentication attempt
  #
  # @param method [String] Auth method
  # @param reason [String] Failure reason
  # @param request [ActionDispatch::Request]
  def log_auth_failure(method, reason, request)
    Rails.logger.warn({
      event: 'authentication_failure',
      method: method,
      reason: reason,
      ip: request.ip,
      path: request.path,
      user_agent: request.user_agent
    }.to_json)
  end

  # Return 401 Unauthorized response
  #
  # @param error_code [String]
  # @param details [String]
  # @return [Array] Rack response
  def unauthorized_response(error_code, details)
    body = {
      success: false,
      error: {
        code: error_code,
        message: details
      }
    }.to_json

    [
      401,
      {
        'Content-Type' => 'application/json',
        'WWW-Authenticate' => 'Bearer realm="API Gateway"'
      },
      [body]
    ]
  end

  # Return 500 Internal Server Error response
  #
  # @return [Array] Rack response
  def internal_error_response
    body = {
      success: false,
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred during authentication.'
      }
    }.to_json

    [
      500,
      { 'Content-Type' => 'application/json' },
      [body]
    ]
  end
end
