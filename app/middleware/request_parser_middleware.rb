# frozen_string_literal: true

# RequestParserMiddleware extracts and validates request metadata
# Runs first in the middleware pipeline
# Responsibilities:
# - Generate unique request ID
# - Extract client IP
# - Parse and validate headers
# - Extract request metadata
class RequestParserMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    # Generate request ID if not present
    request_id = request.headers['X-Request-ID'] || SecureRandom.uuid
    env['HTTP_X_REQUEST_ID'] = request_id

    # Extract client IP (handle proxies)
    client_ip = extract_client_ip(request)
    env['gateway.client_ip'] = client_ip

    # Extract request metadata
    env['gateway.metadata'] = extract_metadata(request)

    # Store request start time for latency tracking
    env['gateway.start_time'] = Time.current

    @app.call(env)
  rescue => e
    Rails.logger.error("RequestParserMiddleware error: #{e.message}")
    error_response(e)
  end

  private

  def extract_client_ip(request)
    # Check X-Forwarded-For header (set by load balancers)
    forwarded_for = request.headers['X-Forwarded-For']
    return forwarded_for.split(',').first.strip if forwarded_for.present?

    # Check X-Real-IP header
    real_ip = request.headers['X-Real-IP']
    return real_ip if real_ip.present?

    # Fallback to remote_ip
    request.remote_ip
  end

  def extract_metadata(request)
    {
      method: request.method,
      path: request.path,
      query_string: request.query_string,
      user_agent: request.user_agent,
      content_type: request.content_type,
      content_length: request.content_length,
      referrer: request.referrer,
      request_id: request.headers['X-Request-ID']
    }
  end

  def error_response(exception)
    [
      400,
      { 'Content-Type' => 'application/json' },
      [{
        success: false,
        error: {
          code: 'BAD_REQUEST',
          message: 'Failed to parse request'
        }
      }.to_json]
    ]
  end
end
