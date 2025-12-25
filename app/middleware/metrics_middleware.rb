# frozen_string_literal: true

# Metrics Middleware
#
# Automatically tracks metrics for all requests:
# - Request count and throughput
# - Response times
# - Status codes
# - Errors
#
# Integrates with MetricsService for storage and aggregation
class MetricsMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    start_time = Time.current

    # Call next middleware/controller
    status, headers, response = @app.call(env)

    # Calculate response time
    response_time = ((Time.current - start_time) * 1000).round(2) # milliseconds

    # Record metrics
    record_metrics(
      request: request,
      status_code: status,
      response_time: response_time,
      env: env
    )

    [status, headers, response]

  rescue StandardError => e
    # Record error metrics
    record_error_metrics(
      request: request,
      error: e,
      env: env
    )

    # Re-raise the error so it's handled by exception handler
    raise e
  end

  private

  # Record successful request metrics
  def record_metrics(request:, status_code:, response_time:, env:)
    # Skip metrics for assets and health checks to reduce noise
    return if skip_metrics?(request.path)

    user_id = env['current_user']&.id
    endpoint = normalize_endpoint(request.path)

    MetricsService.record_request(
      endpoint: endpoint,
      method: request.method,
      user_id: user_id,
      response_time: response_time,
      status_code: status_code
    )

    # Log slow requests (> 1 second)
    if response_time > 1000
      Rails.logger.warn({
        event: 'slow_request',
        endpoint: endpoint,
        method: request.method,
        response_time: response_time,
        user_id: user_id,
        ip: request.ip
      }.to_json)
    end

  rescue StandardError => e
    # Don't let metrics recording crash the app
    Rails.logger.error("Metrics recording error: #{e.message}")
  end

  # Record error metrics
  def record_error_metrics(request:, error:, env:)
    return if skip_metrics?(request.path)

    user_id = env['current_user']&.id
    endpoint = normalize_endpoint(request.path)
    error_type = classify_error(error)

    MetricsService.record_error(
      error_type: error_type,
      endpoint: endpoint,
      message: error.message,
      user_id: user_id,
      metadata: {
        error_class: error.class.name,
        method: request.method,
        ip: request.ip,
        user_agent: request.user_agent
      }
    )

  rescue StandardError => e
    Rails.logger.error("Error metrics recording error: #{e.message}")
  end

  # Check if we should skip metrics for this path
  def skip_metrics?(path)
    skip_patterns = [
      '/assets/',
      '/health',
      '/favicon.ico',
      '/robots.txt'
    ]

    skip_patterns.any? { |pattern| path.start_with?(pattern) }
  end

  # Normalize endpoint to group similar paths
  # e.g., /api_keys/123 -> /api_keys/:id
  def normalize_endpoint(path)
    # Remove query string
    path = path.split('?').first

    # Replace UUIDs and numeric IDs with placeholders
    path = path.gsub(/\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, '/:uuid')
    path = path.gsub(/\/\d+/, '/:id')

    path
  end

  # Classify error type for metrics
  def classify_error(error)
    case error
    when ActiveRecord::RecordNotFound
      'not_found_error'
    when ActionController::ParameterMissing, ActiveRecord::RecordInvalid
      'validation_error'
    when JwtService::TokenExpiredError, JwtService::TokenInvalidError
      'authentication_error'
    when StandardError
      if error.message.include?('Forbidden') || error.message.include?('Admin access')
        'authorization_error'
      elsif error.message.include?('rate limit')
        'rate_limit_error'
      else
        'server_error'
      end
    else
      'unknown_error'
    end
  end
end
