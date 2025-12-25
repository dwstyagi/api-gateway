# frozen_string_literal: true

# Metrics Service
#
# Tracks and aggregates metrics for:
# - Request/response logging
# - Performance monitoring (response times, throughput)
# - Error tracking
# - API usage statistics
#
# Uses Redis for real-time metrics storage with TTL
class MetricsService
  # Metric types
  METRIC_TYPES = %w[request response error performance].freeze

  # Time windows for aggregation
  WINDOWS = {
    minute: 60,
    hour: 3600,
    day: 86400,
    week: 604800
  }.freeze

  class << self
    # Record a successful API request
    #
    # @param endpoint [String] API endpoint path
    # @param method [String] HTTP method
    # @param user_id [Integer] User ID
    # @param response_time [Float] Response time in milliseconds
    # @param status_code [Integer] HTTP status code
    def record_request(endpoint:, method:, user_id: nil, response_time: nil, status_code: 200)
      timestamp = Time.current.to_i

      # Increment request counters
      increment_counter('requests:total')
      increment_counter("requests:endpoint:#{sanitize_key(endpoint)}")
      increment_counter("requests:method:#{method}")
      increment_counter("requests:status:#{status_code}")
      increment_counter("requests:user:#{user_id}") if user_id

      # Record response time
      if response_time
        record_response_time(endpoint, response_time)
        record_response_time('global', response_time)
      end

      # Store detailed request log (24 hour TTL)
      log_key = "request_log:#{timestamp}:#{SecureRandom.hex(4)}"
      $redis.setex(log_key, 86400, {
        endpoint: endpoint,
        method: method,
        user_id: user_id,
        response_time: response_time,
        status_code: status_code,
        timestamp: timestamp
      }.to_json)

      # Add to time-series data for each window
      WINDOWS.each do |window_name, window_size|
        bucket = (timestamp / window_size) * window_size
        bucket_key = "timeseries:requests:#{window_name}:#{bucket}"
        $redis.hincrby(bucket_key, endpoint, 1)
        $redis.expire(bucket_key, window_size * 2) # Keep for 2x window size
      end
    end

    # Record an error
    #
    # @param error_type [String] Type of error
    # @param endpoint [String] API endpoint path
    # @param message [String] Error message
    # @param user_id [Integer] User ID
    # @param metadata [Hash] Additional error context
    def record_error(error_type:, endpoint: nil, message: nil, user_id: nil, metadata: {})
      timestamp = Time.current.to_i

      # Increment error counters
      increment_counter('errors:total')
      increment_counter("errors:type:#{error_type}")
      increment_counter("errors:endpoint:#{sanitize_key(endpoint)}") if endpoint
      increment_counter("errors:user:#{user_id}") if user_id

      # Store detailed error log (7 day TTL)
      log_key = "error_log:#{timestamp}:#{SecureRandom.hex(4)}"
      $redis.setex(log_key, 604800, {
        error_type: error_type,
        endpoint: endpoint,
        message: message,
        user_id: user_id,
        metadata: metadata,
        timestamp: timestamp
      }.to_json)

      # Check if error rate is above threshold for alerting
      check_error_threshold(error_type)
    end

    # Record response time for performance monitoring
    #
    # @param endpoint [String] API endpoint path
    # @param response_time [Float] Response time in milliseconds
    def record_response_time(endpoint, response_time)
      key = "response_times:#{sanitize_key(endpoint)}"

      # Use sorted set to track percentiles
      $redis.zadd(key, response_time, "#{Time.current.to_f}:#{SecureRandom.hex(4)}")
      $redis.expire(key, 3600) # Keep for 1 hour

      # Also track in histogram buckets for faster aggregation
      bucket = response_time_bucket(response_time)
      histogram_key = "response_histogram:#{sanitize_key(endpoint)}"
      $redis.hincrby(histogram_key, bucket, 1)
      $redis.expire(histogram_key, 3600)
    end

    # Get request statistics
    #
    # @param window [Symbol] Time window (:minute, :hour, :day, :week)
    # @return [Hash] Request statistics
    def get_request_stats(window: :hour)
      {
        total: get_counter('requests:total'),
        by_endpoint: get_top_endpoints(window),
        by_method: get_by_method,
        by_status: get_by_status,
        throughput: calculate_throughput(window)
      }
    end

    # Get error statistics
    #
    # @return [Hash] Error statistics
    def get_error_stats
      {
        total: get_counter('errors:total'),
        by_type: get_errors_by_type,
        recent_errors: get_recent_errors(limit: 20),
        error_rate: calculate_error_rate
      }
    end

    # Get performance statistics
    #
    # @param endpoint [String] API endpoint path (optional, nil for global)
    # @return [Hash] Performance statistics
    def get_performance_stats(endpoint: nil)
      key = endpoint ? "response_times:#{sanitize_key(endpoint)}" : 'response_times:global'

      response_times = $redis.zrange(key, 0, -1, with_scores: true).map { |_, score| score }

      return {} if response_times.empty?

      sorted_times = response_times.sort
      count = sorted_times.length

      {
        count: count,
        min: sorted_times.first,
        max: sorted_times.last,
        avg: sorted_times.sum / count,
        p50: percentile(sorted_times, 50),
        p95: percentile(sorted_times, 95),
        p99: percentile(sorted_times, 99)
      }
    end

    # Get throughput (requests per second)
    #
    # @param window [Symbol] Time window
    # @return [Float] Requests per second
    def calculate_throughput(window = :minute)
      total_requests = get_counter('requests:total')
      window_size = WINDOWS[window] || 60

      # Get requests from start of window
      window_start = Time.current.to_i - window_size
      recent_requests = get_requests_since(window_start)

      recent_requests.to_f / window_size
    end

    # Calculate error rate (errors per total requests)
    #
    # @return [Float] Error rate as percentage
    def calculate_error_rate
      total_requests = get_counter('requests:total')
      total_errors = get_counter('errors:total')

      return 0.0 if total_requests.zero?

      (total_errors.to_f / total_requests * 100).round(2)
    end

    # Reset all metrics (useful for testing)
    def reset_all!
      keys = $redis.keys('requests:*') +
             $redis.keys('errors:*') +
             $redis.keys('response_times:*') +
             $redis.keys('response_histogram:*') +
             $redis.keys('timeseries:*')

      $redis.del(*keys) if keys.any?
    end

    private

    # Increment a counter with 24 hour TTL
    def increment_counter(key, by = 1)
      $redis.incrby(key, by)
      $redis.expire(key, 86400) unless $redis.ttl(key) > 0
    end

    # Get counter value
    def get_counter(key)
      ($redis.get(key) || 0).to_i
    end

    # Sanitize key for Redis
    def sanitize_key(key)
      return 'unknown' if key.nil?
      key.to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '_')
    end

    # Determine response time bucket for histogram
    def response_time_bucket(ms)
      case ms
      when 0..10 then '0-10ms'
      when 11..50 then '11-50ms'
      when 51..100 then '51-100ms'
      when 101..500 then '101-500ms'
      when 501..1000 then '501-1000ms'
      else '1000ms+'
      end
    end

    # Calculate percentile from sorted array
    def percentile(sorted_array, percentile)
      return 0 if sorted_array.empty?

      k = (percentile / 100.0) * (sorted_array.length - 1)
      f = k.floor
      c = k.ceil

      if f == c
        sorted_array[k.to_i]
      else
        sorted_array[f] * (c - k) + sorted_array[c] * (k - f)
      end
    end

    # Get top endpoints by request count
    def get_top_endpoints(window = :hour, limit = 10)
      timestamp = Time.current.to_i
      window_size = WINDOWS[window]
      bucket = (timestamp / window_size) * window_size
      bucket_key = "timeseries:requests:#{window}:#{bucket}"

      endpoints = $redis.hgetall(bucket_key)
      endpoints.map { |k, v| [k, v.to_i] }
               .sort_by { |_, count| -count }
               .first(limit)
               .to_h
    end

    # Get requests by HTTP method
    def get_by_method
      %w[GET POST PUT PATCH DELETE].each_with_object({}) do |method, hash|
        hash[method] = get_counter("requests:method:#{method}")
      end
    end

    # Get requests by status code
    def get_by_status
      [200, 201, 204, 400, 401, 403, 404, 422, 429, 500, 502, 503].each_with_object({}) do |status, hash|
        count = get_counter("requests:status:#{status}")
        hash[status] = count if count > 0
      end
    end

    # Get errors by type
    def get_errors_by_type
      error_types = %w[
        validation_error
        authentication_error
        authorization_error
        not_found_error
        rate_limit_error
        server_error
        gateway_error
      ]

      error_types.each_with_object({}) do |type, hash|
        count = get_counter("errors:type:#{type}")
        hash[type] = count if count > 0
      end
    end

    # Get recent error logs
    def get_recent_errors(limit: 20)
      pattern = 'error_log:*'
      keys = $redis.keys(pattern).last(limit)

      keys.map do |key|
        JSON.parse($redis.get(key) || '{}')
      end.compact.sort_by { |e| -e['timestamp'] }
    end

    # Get request count since timestamp
    def get_requests_since(timestamp)
      # This is an approximation - in production you'd query time-series data
      # For now, return total counter as baseline
      get_counter('requests:total')
    end

    # Check if error rate exceeds threshold
    def check_error_threshold(error_type)
      count = get_counter("errors:type:#{error_type}")

      # Alert if more than 100 errors of same type in last hour
      if count > 100
        Rails.logger.error("HIGH ERROR RATE ALERT: #{error_type} has #{count} occurrences")
        # TODO: Integrate with AlertingService when implemented
      end
    end
  end
end
