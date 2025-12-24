# frozen_string_literal: true

# Base class for all Gateway-specific errors
# Provides standardized error responses with HTTP status codes
class GatewayError < StandardError
  attr_reader :error_code, :status, :details

  def initialize(message, error_code:, status:, details: {})
    super(message)
    @error_code = error_code
    @status = status
    @details = details
  end

  def to_response
    {
      success: false,
      error: {
        code: error_code,
        message: message,
        details: details
      }
    }
  end
end
