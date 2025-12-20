# frozen_string_literal: true

module Api
  # Users Controller
  #
  # Protected endpoint requiring authentication

  class UsersController < ApiController
    # GET /api/me
    # Get current authenticated user info
    def me
      render json: {
        success: true,
        data: {
          user: {
            id: current_user.id,
            email: current_user.email,
            role: current_user.role,
            tier: current_user.tier,
            token_version: current_user.token_version,
            created_at: current_user.created_at
          },
          auth_method: auth_method,
          api_key: current_api_key ? {
            id: current_api_key.id,
            name: current_api_key.name,
            scopes: current_api_key.scopes,
            last_used_at: current_api_key.last_used_at
          } : nil
        }
      }
    end
  end
end
