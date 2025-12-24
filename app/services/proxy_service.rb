# frozen_string_literal: true

require 'httparty'

# ProxyService handles forwarding requests to backend services
# Features:
# - Request/response transformation
# - Retry logic with exponential backoff
# - Circuit breaker pattern
# - Timeout configuration
class ProxyService
  include HTTParty

  # Default configuration
  DEFAULT_TIMEOUT = 30 # seconds
  DEFAULT_RETRIES = 2
  RETRY_STATUSES = [502, 503, 504].freeze
  CIRCUIT_BREAKER_THRESHOLD = 5
  CIRCUIT_BREAKER_TIMEOUT = 30 # seconds

  attr_reader :api_definition, :circuit_breaker

  def initialize(api_definition)
    @api_definition = api_definition
    @circuit_breaker = CircuitBreaker.instance(api_definition.id)
  end

  # Forward the request to the backend service
  # @param request [ActionDispatch::Request] The incoming request
  # @param path [String] The path to forward to
  # @return [Hash] Response with status, headers, and body
  def forward(request, path)
    raise ApiDisabledError unless api_definition.enabled?

    # Check circuit breaker
    raise UpstreamError.new("Circuit breaker is open") if circuit_breaker.open?

    # Build the full backend URL
    backend_url = build_backend_url(path)

    # Execute request with retries
    response = execute_with_retry(request, backend_url)

    # Record success in circuit breaker
    circuit_breaker.record_success

    # Transform response
    transform_response(response)
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    circuit_breaker.record_failure
    Rails.logger.error("Proxy error: #{e.message}")
    raise UpstreamTimeoutError.new(e.message)
  rescue UpstreamError => e
    circuit_breaker.record_failure
    raise e
  end

  private

  def build_backend_url(path)
    backend_base = api_definition.backend_url.chomp('/')
    clean_path = path.start_with?('/') ? path : "/#{path}"
    "#{backend_base}#{clean_path}"
  end

  def execute_with_retry(request, url)
    retries = 0
    begin
      execute_request(request, url)
    rescue UpstreamError => e
      retries += 1
      if retries <= DEFAULT_RETRIES && RETRY_STATUSES.include?(e.details[:upstream_status])
        sleep_duration = backoff_duration(retries)
        Rails.logger.warn("Retrying request (attempt #{retries}/#{DEFAULT_RETRIES}) after #{sleep_duration}s")
        sleep(sleep_duration)
        retry
      else
        raise e
      end
    end
  end

  def execute_request(request, url)
    # Prepare request options
    options = {
      headers: forward_headers(request),
      timeout: DEFAULT_TIMEOUT,
      follow_redirects: false
    }

    # Add body for POST/PUT/PATCH
    if ['POST', 'PUT', 'PATCH'].include?(request.method)
      options[:body] = request.raw_post
    end

    # Add query parameters
    options[:query] = request.query_parameters if request.query_parameters.any?

    # Execute HTTP request
    Rails.logger.info("Proxying #{request.method} #{url}")
    response = self.class.send(request.method.downcase.to_sym, url, options)

    # Check for upstream errors
    if response.code >= 500
      raise UpstreamError.new(
        "Backend returned error status #{response.code}",
        upstream_status: response.code
      )
    end

    response
  end

  def forward_headers(request)
    # Forward specific headers to backend
    headers = {}

    # Forward standard headers
    forward_header_list = [
      'Content-Type',
      'Accept',
      'Accept-Language',
      'User-Agent',
      'X-Request-ID'
    ]

    forward_header_list.each do |header|
      value = request.headers[header]
      headers[header] = value if value.present?
    end

    # Add custom gateway headers
    headers['X-Forwarded-For'] = request.remote_ip
    headers['X-Forwarded-Proto'] = request.protocol.sub('://', '')
    headers['X-Forwarded-Host'] = request.host
    headers['X-Gateway-Request-ID'] = request.request_id

    # Forward user context if authenticated
    if request.env['current_user']
      headers['X-User-ID'] = request.env['current_user'].id
      headers['X-User-Tier'] = request.env['current_user'].tier
    end

    headers
  end

  def transform_response(response)
    {
      status: response.code,
      headers: sanitize_response_headers(response.headers),
      body: response.body
    }
  end

  def sanitize_response_headers(headers)
    # Remove headers that shouldn't be forwarded to client
    headers = headers.to_h
    sanitized = headers.except(
      'Transfer-Encoding',
      'Connection',
      'Keep-Alive',
      'Proxy-Authenticate',
      'Proxy-Authorization',
      'TE',
      'Trailers',
      'Upgrade'
    )

    # Convert array values to comma-separated strings
    # HTTParty returns some headers as arrays (like Set-Cookie)
    sanitized.transform_values do |value|
      value.is_a?(Array) ? value.join(', ') : value
    end
  end

  def backoff_duration(retry_count)
    # Exponential backoff: 1s, 2s, 4s, etc.
    2 ** (retry_count - 1)
  end

  # Circuit Breaker implementation
  class CircuitBreaker
    STATES = {
      closed: 'closed',     # Normal operation
      open: 'open',         # Failing, reject requests
      half_open: 'half_open' # Testing if service recovered
    }.freeze

    attr_reader :api_id, :redis

    def self.instance(api_id)
      new(api_id)
    end

    def initialize(api_id)
      @api_id = api_id
      @redis = $redis
    end

    def open?
      state == STATES[:open]
    end

    def state
      redis_state = redis.get(state_key)
      return STATES[:closed] unless redis_state

      # Check if we should transition from open to half-open
      if redis_state == STATES[:open]
        opened_at = redis.get(opened_at_key).to_i
        if Time.current.to_i - opened_at >= CIRCUIT_BREAKER_TIMEOUT
          set_state(STATES[:half_open])
          return STATES[:half_open]
        end
      end

      redis_state
    end

    def record_success
      current_state = state

      if current_state == STATES[:half_open]
        # Service recovered, close circuit
        set_state(STATES[:closed])
        redis.del(failure_count_key)
        Rails.logger.info("Circuit breaker closed for API #{api_id}")
      elsif current_state == STATES[:closed]
        # Reset failure count on success
        redis.set(failure_count_key, 0, ex: 60)
      end
    end

    def record_failure
      current_state = state

      if current_state == STATES[:half_open]
        # Still failing, reopen circuit
        open_circuit
      elsif current_state == STATES[:closed]
        failures = redis.incr(failure_count_key)
        redis.expire(failure_count_key, 60) if failures == 1

        if failures >= CIRCUIT_BREAKER_THRESHOLD
          open_circuit
        end
      end
    end

    private

    def open_circuit
      set_state(STATES[:open])
      redis.set(opened_at_key, Time.current.to_i, ex: CIRCUIT_BREAKER_TIMEOUT + 10)
      Rails.logger.error("Circuit breaker opened for API #{api_id}")
    end

    def set_state(new_state)
      redis.set(state_key, new_state, ex: 300) # 5 minutes TTL
    end

    def state_key
      "circuit_breaker:#{api_id}:state"
    end

    def failure_count_key
      "circuit_breaker:#{api_id}:failures"
    end

    def opened_at_key
      "circuit_breaker:#{api_id}:opened_at"
    end
  end
end
