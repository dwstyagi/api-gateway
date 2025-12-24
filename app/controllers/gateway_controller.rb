# frozen_string_literal: true

# GatewayController handles all proxied API requests
# This is the main entry point for requests coming through the gateway
# Middleware pipeline runs before this controller:
# 1. RequestParserMiddleware - extracts metadata
# 2. AuthenticationMiddleware - validates JWT/API key
# 3. IpRulesMiddleware - checks IP blocklist
# 4. RateLimitingMiddleware - enforces rate limits
# 5. (This controller) - proxies to backend
class GatewayController < ApplicationController
  include ExceptionHandler

  # Disable CSRF for API requests
  skip_before_action :verify_authenticity_token

  # Match all routes and proxy them
  def proxy
    # Get the API definition for this route
    api_definition = find_api_definition

    # Get the path to forward (strip /api/gateway prefix if present)
    forward_path = extract_forward_path

    # Proxy the request
    proxy_service = ProxyService.new(api_definition)
    result = proxy_service.forward(request, forward_path)

    # Set safe headers from upstream (avoid headers that conflict with Rails)
    safe_headers = ['content-type', 'cache-control', 'etag', 'last-modified', 'vary']
    result[:headers].each do |key, value|
      response.headers[key] = value.to_s if safe_headers.include?(key.downcase) && value.present?
    end

    # Add custom gateway headers
    response.headers['X-Gateway-Version'] = '1.0'
    response.headers['X-Gateway-Time'] = Time.current.httpdate

    # Render the response
    content_type = result[:headers]['content-type'] || 'application/json'
    render plain: result[:body], status: result[:status], content_type: content_type
  end

  private

  def find_api_definition
    # Try to match the request path against API definitions
    path = request.path
    method = request.method

    api_def = ApiDefinition.enabled.find do |api|
      path_matches?(path, api.route_pattern) && method_allowed?(method, api.allowed_methods)
    end

    raise RouteNotFoundError.new("No API definition found for #{method} #{path}") unless api_def

    # Store in request env for middleware access
    request.env['api_definition'] = api_def
    api_def
  end

  def path_matches?(request_path, pattern)
    # Convert pattern to regex
    # /api/orders/* matches /api/orders/123, /api/orders/abc, etc.
    # /api/users/:id matches /api/users/123
    regex_pattern = pattern
      .gsub('*', '.*')                    # * becomes .*
      .gsub(':id', '[^/]+')               # :id becomes [^/]+
      .gsub(':uuid', '[a-f0-9\-]+')       # :uuid becomes [a-f0-9\-]+

    regex = /\A#{regex_pattern}\z/
    request_path.match?(regex)
  end

  def method_allowed?(method, allowed_methods)
    allowed_methods.include?(method)
  end

  def extract_forward_path
    # The full path minus the /api prefix
    path = request.path

    # Strip /api prefix from the path
    # /api/posts/1 → /posts/1
    # /api/test/get → /test/get
    path = path.sub(%r{\A/api}, '')

    # If path is empty after stripping, use root
    path = '/' if path.empty?

    # Preserve query string
    path += "?#{request.query_string}" if request.query_string.present?

    path
  end

  def render_proxied_response(result)
    # Add upstream headers to response
    result[:headers].each do |key, value|
      response.headers[key] = value.to_s if value.present?
    end

    # Add custom gateway headers
    response.headers['X-Gateway-Version'] = '1.0'
    response.headers['X-Gateway-Time'] = Time.current.httpdate

    # Determine content type
    content_type = result[:headers]['content-type'] || result[:headers]['Content-Type'] || 'text/plain'

    # Render based on content type
    if content_type.include?('json')
      # Parse and re-render JSON to ensure proper formatting
      begin
        parsed_json = JSON.parse(result[:body])
        render json: parsed_json, status: result[:status]
      rescue JSON::ParserError
        # If parsing fails, render as plain text
        render plain: result[:body].to_s, status: result[:status], content_type: 'application/json'
      end
    else
      render plain: result[:body].to_s, status: result[:status], content_type: content_type
    end
  end
end
