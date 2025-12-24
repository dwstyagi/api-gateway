# frozen_string_literal: true

# Rate Limiting Middleware
#
# Enforces rate limits on incoming requests based on:
# - API endpoint (route pattern)
# - User tier (free, pro, enterprise)
# - Rate limiting strategy (token bucket, sliding window, etc.)
#
# Flow:
# 1. Extract request info (path, method, user)
# 2. Find matching API definition
# 3. Get rate limit policy for user's tier
# 4. Check rate limit using appropriate strategy
# 5. Add rate limit headers to response
# 6. Allow or deny request
#
# Rate Limit Headers (RFC 6585):
#   X-RateLimit-Limit: Maximum requests allowed
#   X-RateLimit-Remaining: Requests remaining in current window
#   X-RateLimit-Reset: Timestamp when limit resets (Unix epoch)
#   Retry-After: Seconds until retry (when rate limited)

class RateLimitingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    # Skip rate limiting for certain paths
    return @app.call(env) if skip_rate_limiting?(request.path)

    # Find API definition matching this request
    api_definition = find_api_definition(request)

    # No rate limiting if no API definition found
    return @app.call(env) unless api_definition

    # Get user tier (from authentication middleware)
    user_tier = get_user_tier(env)

    # Get rate limit policy for this tier
    policy = api_definition.policy_for_tier(user_tier)

    # No rate limiting if no policy configured
    return @app.call(env) unless policy

    # Check rate limit
    result = check_rate_limit(policy, env, request)

    if result.allowed?
      # Request allowed - add rate limit headers and continue
      status, headers, body = @app.call(env)
      add_rate_limit_headers(headers, policy, result)
      [status, headers, body]
    else
      # Request denied - return 429 Too Many Requests
      # Track rate limit abuse for auto-blocking
      AutoBlockerService.record_rate_limit_abuse(request.ip)
      rate_limited_response(policy, result)
    end
  rescue StandardError => e
    # On error, log and either fail-open or fail-closed based on policy
    Rails.logger.error("Rate limiting error: #{e.message}\n#{e.backtrace.join("\n")}")

    # If no policy, fail-open by default
    return @app.call(env) unless policy

    if policy.redis_failure_mode == 'open'
      # Fail-open: Allow request
      @app.call(env)
    else
      # Fail-closed: Deny request
      error_response(e)
    end
  end

  private

  # Skip rate limiting for certain paths
  def skip_rate_limiting?(path)
    # Skip health checks and auth endpoints
    path == '/health' || path.start_with?('/auth/')
  end

  # Find API definition matching the request
  def find_api_definition(request)
    path = request.path
    method = request.method

    # Check cache first (avoid DB query on every request)
    cache_key = "api_def:#{method}:#{path}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    # Find matching definition in database
    api_def = ApiDefinition.enabled.find do |definition|
      definition.matches_route?(path) && definition.method_allowed?(method)
    end

    # Cache for 5 minutes
    Rails.cache.write(cache_key, api_def, expires_in: 5.minutes) if api_def

    api_def
  end

  # Get user tier from environment (set by authentication middleware)
  def get_user_tier(env)
    current_user = env['current_user']
    return nil unless current_user

    current_user.tier
  end

  # Generate rate limit identifier (user ID or API key or IP)
  def rate_limit_identifier(env, request)
    # Priority: User ID > API Key > IP Address
    current_user = env['current_user']
    api_key = env['api_key']

    if current_user
      "user:#{current_user.id}"
    elsif api_key
      "apikey:#{api_key.id}"
    else
      "ip:#{request.ip}"
    end
  end

  # Check rate limit using appropriate strategy
  def check_rate_limit(policy, env, request)
    identifier = rate_limit_identifier(env, request)

    # Create rate limiter for this strategy
    limiter = RateLimiterFactory.create(policy)

    # For concurrency limiter, need to acquire and release
    if policy.strategy == 'concurrency'
      result = limiter.acquire(identifier)

      # Store limiter and identifier in env for release in after_action
      # (This would typically be handled by a controller concern)
      env['rate_limiter'] = limiter
      env['rate_limit_identifier'] = identifier

      result
    else
      # For other strategies, just check limit
      limiter.check_limit(identifier)
    end
  end

  # Add rate limit headers to response
  def add_rate_limit_headers(headers, policy, result)
    headers['X-RateLimit-Limit'] = policy.capacity.to_s
    headers['X-RateLimit-Remaining'] = result.remaining.to_s if result.remaining

    # Calculate reset time based on strategy
    if policy.window_seconds
      # Window-based strategies
      window_seconds = policy.window_seconds
      current_window_start = (Time.now.to_i / window_seconds) * window_seconds
      reset_time = current_window_start + window_seconds
      headers['X-RateLimit-Reset'] = reset_time.to_s
    elsif policy.refill_rate
      # Token/Leaky bucket strategies
      # Estimate reset time based on refill rate
      seconds_to_full = (policy.capacity - (result.remaining || 0)) / policy.refill_rate
      reset_time = Time.now.to_i + seconds_to_full.ceil
      headers['X-RateLimit-Reset'] = reset_time.to_s
    end
  end

  # Return 429 Too Many Requests response
  def rate_limited_response(policy, result)
    retry_after_seconds = result.retry_after_seconds

    headers = {
      'Content-Type' => 'application/json',
      'X-RateLimit-Limit' => policy.capacity.to_s,
      'X-RateLimit-Remaining' => '0',
      'Retry-After' => retry_after_seconds.ceil.to_s
    }

    body = {
      success: false,
      error: {
        code: 'RATE_LIMIT_EXCEEDED',
        message: 'Too many requests. Please slow down.',
        retry_after_seconds: retry_after_seconds,
        strategy: policy.strategy
      }
    }.to_json

    [429, headers, [body]]
  end

  # Return 500 error response
  def error_response(error)
    headers = {
      'Content-Type' => 'application/json'
    }

    body = {
      success: false,
      error: {
        code: 'RATE_LIMITER_ERROR',
        message: 'Rate limiting service unavailable. Please try again later.'
      }
    }.to_json

    [503, headers, [body]]
  end
end
