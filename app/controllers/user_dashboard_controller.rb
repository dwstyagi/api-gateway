# frozen_string_literal: true

# User Dashboard Controller
#
# Self-service portal for regular users to:
# - View and manage their own API keys
# - See their usage statistics
# - View their activity logs
class UserDashboardController < ApplicationController
  before_action :require_user

  def index
    @user = current_user

    # Get user's API keys
    @api_keys = @user.api_keys.order(created_at: :desc)

    # Get usage statistics
    @stats = {
      total_keys: @api_keys.count,
      active_keys: @api_keys.where(status: 'active').count,
      revoked_keys: @api_keys.where(status: 'revoked').count,
      tier: @user.tier,
      role: @user.role
    }

    # Get recent activity (last 10 events)
    @recent_activity = AuditLog.where(user_id: @user.id)
                                .order(created_at: :desc)
                                .limit(10)

    # API key creation over time (last 30 days)
    @keys_by_day = @api_keys.where('created_at > ?', 30.days.ago)
                            .group_by_day(:created_at)
                            .count
  end

  private

  def require_user
    unless current_user
      redirect_to login_path, alert: 'Please login to continue'
    end
  end
end
