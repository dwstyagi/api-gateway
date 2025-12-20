# frozen_string_literal: true

# Authenticatable Concern
#
# Provides helper methods for controllers to access authentication context
# set by AuthenticationMiddleware
#
# Usage:
#   class ApiController < ApplicationController
#     include Authenticatable
#
#     def show
#       render json: { user: current_user.email }
#     end
#   end

module Authenticatable
  extend ActiveSupport::Concern

  included do
    # Make these methods available as helper methods in views
    helper_method :current_user, :authenticated?, :auth_method, :current_api_key if respond_to?(:helper_method)
  end

  # Get the currently authenticated user
  #
  # @return [User, nil]
  def current_user
    request.env['current_user']
  end

  # Check if request is authenticated
  #
  # @return [Boolean]
  def authenticated?
    current_user.present?
  end

  # Get the authentication method used
  #
  # @return [String, nil] 'jwt' or 'api_key'
  def auth_method
    request.env['auth_method']
  end

  # Get the current API key (if authenticated via API key)
  #
  # @return [ApiKey, nil]
  def current_api_key
    request.env['api_key']
  end

  # Check if current user is an admin
  #
  # @return [Boolean]
  def admin?
    current_user&.admin? || false
  end

  # Require admin role
  # Use as before_action in controllers
  #
  # Example:
  #   class Admin::UsersController < ApplicationController
  #     before_action :require_admin
  #   end
  def require_admin
    unless admin?
      render json: {
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: 'Admin access required'
        }
      }, status: :forbidden
    end
  end

  # Check if current API key has required scope
  #
  # @param scope [String] Required scope (e.g., "orders:write")
  # @return [Boolean]
  def has_scope?(scope)
    return true if auth_method == 'jwt' # JWTs have full access

    current_api_key&.has_scope?(scope) || false
  end

  # Require specific scope
  # Use as before_action in controllers
  #
  # Example:
  #   class OrdersController < ApplicationController
  #     before_action -> { require_scope('orders:write') }, only: [:create, :update]
  #   end
  #
  # @param scope [String] Required scope
  def require_scope(scope)
    unless has_scope?(scope)
      render json: {
        success: false,
        error: {
          code: 'INSUFFICIENT_SCOPE',
          message: "This action requires scope: #{scope}"
        }
      }, status: :forbidden
    end
  end
end
