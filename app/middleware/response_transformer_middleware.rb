# frozen_string_literal: true

# ResponseTransformerMiddleware modifies responses before sending to clients
# Runs after the application processes the request
# Responsibilities:
# - Add security headers
# - Add custom gateway headers
# - Sanitize response headers
# - Add CORS headers if configured
class ResponseTransformerMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    # Transform headers
    headers = add_security_headers(headers)
    headers = add_gateway_headers(headers, env)
    headers = add_cors_headers(headers, env) if cors_enabled?

    [status, headers, body]
  end

  private

  def add_security_headers(headers)
    # Add security headers if not already present
    headers['X-Content-Type-Options'] ||= 'nosniff'
    headers['X-Frame-Options'] ||= 'DENY'
    headers['X-XSS-Protection'] ||= '1; mode=block'
    headers['Referrer-Policy'] ||= 'strict-origin-when-cross-origin'

    # Remove server header to hide implementation details
    headers.delete('Server')

    headers
  end

  def add_gateway_headers(headers, env)
    # Add gateway identification headers
    headers['X-Gateway'] = 'API-Gateway/1.0'

    # Add request ID for tracing
    if env['HTTP_X_REQUEST_ID']
      headers['X-Request-ID'] = env['HTTP_X_REQUEST_ID']
    end

    # Add response time
    if env['gateway.start_time']
      duration_ms = ((Time.current - env['gateway.start_time']) * 1000).round(2)
      headers['X-Response-Time'] = "#{duration_ms}ms"
    end

    headers
  end

  def add_cors_headers(headers, env)
    request = ActionDispatch::Request.new(env)

    # Allow all origins in development, specific origins in production
    allowed_origins = Rails.env.development? ? '*' : ENV.fetch('CORS_ALLOWED_ORIGINS', '').split(',')

    origin = request.headers['Origin']
    if allowed_origins.include?('*') || allowed_origins.include?(origin)
      headers['Access-Control-Allow-Origin'] = origin || '*'
      headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
      headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, X-API-Key, X-Request-ID'
      headers['Access-Control-Expose-Headers'] = 'X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset'
      headers['Access-Control-Max-Age'] = '86400' # 24 hours
    end

    headers
  end

  def cors_enabled?
    # CORS is enabled by default in development, configurable in production
    Rails.env.development? || ENV['CORS_ENABLED'] == 'true'
  end
end
