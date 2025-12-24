# frozen_string_literal: true

# LoggerMiddleware provides comprehensive request/response logging
# Runs last in the middleware pipeline (wraps everything)
# Responsibilities:
# - Log all requests with metadata
# - Log response status and timing
# - Log errors and exceptions
# - Store logs in database for analytics
class LoggerMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    start_time = Time.current
    request = ActionDispatch::Request.new(env)

    # Log incoming request
    log_request(request, env)

    # Process request
    status, headers, body = @app.call(env)

    # Calculate duration
    duration_ms = ((Time.current - start_time) * 1000).round(2)

    # Log response
    log_response(request, env, status, duration_ms)

    [status, headers, body]
  rescue => e
    # Log error
    duration_ms = ((Time.current - start_time) * 1000).round(2)
    log_error(request, env, e, duration_ms)
    raise e
  end

  private

  def log_request(request, env)
    metadata = env['gateway.metadata'] || {}
    client_ip = env['gateway.client_ip'] || request.remote_ip

    log_data = {
      timestamp: Time.current.iso8601,
      request_id: request.headers['X-Request-ID'],
      method: request.method,
      path: request.path,
      query: request.query_string,
      ip: client_ip,
      user_agent: request.user_agent,
      user_id: env['current_user']&.id,
      api_key_id: env['current_api_key']&.id
    }

    Rails.logger.info("Gateway Request: #{log_data.to_json}")
  end

  def log_response(request, env, status, duration_ms)
    client_ip = env['gateway.client_ip'] || request.remote_ip
    user = env['current_user']
    api_definition = env['api_definition']

    log_data = {
      timestamp: Time.current.iso8601,
      request_id: request.headers['X-Request-ID'],
      method: request.method,
      path: request.path,
      status: status,
      duration_ms: duration_ms,
      ip: client_ip,
      user_id: user&.id,
      api_id: api_definition&.id,
      api_name: api_definition&.name
    }

    # Choose log level based on status
    if status >= 500
      Rails.logger.error("Gateway Response: #{log_data.to_json}")
    elsif status >= 400
      Rails.logger.warn("Gateway Response: #{log_data.to_json}")
    else
      Rails.logger.info("Gateway Response: #{log_data.to_json}")
    end

    # Store in database for analytics (async)
    store_request_log_async(log_data, env) if should_persist_log?(status)
  end

  def log_error(request, env, exception, duration_ms)
    client_ip = env['gateway.client_ip'] || request.remote_ip

    log_data = {
      timestamp: Time.current.iso8601,
      request_id: request.headers['X-Request-ID'],
      method: request.method,
      path: request.path,
      error: exception.class.name,
      message: exception.message,
      duration_ms: duration_ms,
      ip: client_ip,
      user_id: env['current_user']&.id
    }

    Rails.logger.error("Gateway Error: #{log_data.to_json}")
    Rails.logger.error(exception.backtrace.first(10).join("\n")) if exception.backtrace
  end

  def should_persist_log?(status)
    # Persist successful requests and errors, skip 4xx client errors to save space
    status < 400 || status >= 500
  end

  def store_request_log_async(log_data, env)
    # In production, this would be an async job (Sidekiq, etc.)
    # For now, we'll skip database persistence to keep it simple
    # You can enable this in production with:
    # RequestLogJob.perform_async(log_data, env)

    # Store in Redis for recent logs (keep last 1000)
    begin
      $redis.lpush('gateway:recent_logs', log_data.to_json)
      $redis.ltrim('gateway:recent_logs', 0, 999)
      $redis.expire('gateway:recent_logs', 3600) # 1 hour
    rescue => e
      Rails.logger.warn("Failed to store log in Redis: #{e.message}")
    end
  end
end
