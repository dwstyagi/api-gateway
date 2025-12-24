# frozen_string_literal: true

# Gateway-specific operational errors

class IpBlockedError < GatewayError
  def initialize(message = "Your IP address has been blocked", reason: nil)
    details = reason ? { reason: reason } : {}
    super(message, error_code: "IP_BLOCKED", status: :forbidden, details: details)
  end
end

class ApiDisabledError < GatewayError
  def initialize(message = "This API endpoint is currently disabled")
    super(message, error_code: "API_DISABLED", status: :forbidden)
  end
end

class RateLimitExceededError < GatewayError
  def initialize(message = "Rate limit exceeded", limit:, remaining:, reset_at:, retry_after: nil)
    details = {
      limit: limit,
      remaining: remaining,
      reset_at: reset_at
    }
    details[:retry_after_seconds] = retry_after if retry_after
    super(message, error_code: "RATE_LIMIT_EXCEEDED", status: :too_many_requests, details: details)
  end
end

class UpstreamError < GatewayError
  def initialize(message = "Backend service returned an error", upstream_status: nil)
    details = upstream_status ? { upstream_status: upstream_status } : {}
    super(message, error_code: "UPSTREAM_ERROR", status: :bad_gateway, details: details)
  end
end

class UpstreamTimeoutError < GatewayError
  def initialize(message = "Backend service did not respond in time")
    super(message, error_code: "UPSTREAM_TIMEOUT", status: :gateway_timeout)
  end
end

class RouteNotFoundError < GatewayError
  def initialize(message = "No API definition found for this route")
    super(message, error_code: "ROUTE_NOT_FOUND", status: :not_found)
  end
end

class BadRequestError < GatewayError
  def initialize(message = "Malformed request", field: nil, reason: nil)
    details = {}
    details[:field] = field if field
    details[:reason] = reason if reason
    super(message, error_code: "BAD_REQUEST", status: :bad_request, details: details)
  end
end
