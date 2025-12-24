# frozen_string_literal: true

# Authentication-related errors

class MissingTokenError < GatewayError
  def initialize(message = "No authentication token provided")
    super(message, error_code: "MISSING_TOKEN", status: :unauthorized)
  end
end

class InvalidTokenError < GatewayError
  def initialize(message = "Token is invalid or malformed")
    super(message, error_code: "INVALID_TOKEN", status: :unauthorized)
  end
end

class TokenExpiredError < GatewayError
  def initialize(message = "Token has expired")
    super(message, error_code: "TOKEN_EXPIRED", status: :unauthorized)
  end
end

class TokenRevokedError < GatewayError
  def initialize(message = "Token has been revoked")
    super(message, error_code: "TOKEN_REVOKED", status: :unauthorized)
  end
end

class InvalidApiKeyError < GatewayError
  def initialize(message = "API key is invalid or not found")
    super(message, error_code: "INVALID_API_KEY", status: :unauthorized)
  end
end

class InsufficientScopeError < GatewayError
  def initialize(message = "Insufficient permissions for this action", required_scope: nil)
    details = required_scope ? { required_scope: required_scope } : {}
    super(message, error_code: "INSUFFICIENT_SCOPE", status: :forbidden, details: details)
  end
end
