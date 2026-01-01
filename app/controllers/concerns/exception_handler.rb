# frozen_string_literal: true

# Global exception handler for controllers
# Catches all GatewayError exceptions and returns standardized JSON responses
module ExceptionHandler
  extend ActiveSupport::Concern

  included do
    rescue_from GatewayError, with: :handle_gateway_error
    rescue_from StandardError, with: :handle_standard_error
  end

  private

  def handle_gateway_error(exception)
    Rails.logger.error("GatewayError: #{exception.class.name} - #{exception.message}")
    Rails.logger.error(exception.backtrace.first(5).join("\n")) if exception.backtrace

    # Add rate limit headers if it's a rate limit error
    if exception.is_a?(RateLimitExceededError)
      response.headers['X-RateLimit-Limit'] = exception.details[:limit].to_s
      response.headers['X-RateLimit-Remaining'] = exception.details[:remaining].to_s
      response.headers['X-RateLimit-Reset'] = exception.details[:reset_at].to_s
      response.headers['Retry-After'] = exception.details[:retry_after_seconds].to_i.to_s if exception.details[:retry_after_seconds]
    end

    respond_to do |format|
      format.html do
        flash[:alert] = exception.message
        redirect_to login_path
      end
      format.json do
        render json: exception.to_response, status: exception.status
      end
    end
  end

  def handle_standard_error(exception)
    Rails.logger.error("StandardError: #{exception.class.name} - #{exception.message}")
    Rails.logger.error(exception.backtrace.first(10).join("\n")) if exception.backtrace

    # Don't expose internal errors to clients in production
    message = Rails.env.production? ? "An internal error occurred" : exception.message

    respond_to do |format|
      format.html do
        flash[:alert] = "An error occurred: #{message}"
        redirect_to root_path
      end
      format.json do
        render json: {
          success: false,
          error: {
            code: "INTERNAL_ERROR",
            message: message
          }
        }, status: :internal_server_error
      end
    end
  end
end
