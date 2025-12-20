# frozen_string_literal: true

# Base controller for all API endpoints
#
# Includes authentication helpers and sets JSON response format

class ApiController < ApplicationController
  include Authenticatable
  include RateLimitable

  # Skip CSRF token verification for API requests
  skip_before_action :verify_authenticity_token

  # Rescue from common errors and return JSON responses
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

  private

  def not_found
    render json: {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: 'The requested resource was not found'
      }
    }, status: :not_found
  end

  def unprocessable_entity(exception)
    render json: {
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: exception.message,
        details: exception.record&.errors&.full_messages
      }
    }, status: :unprocessable_entity
  end
end
