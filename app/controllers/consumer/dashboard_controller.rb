# frozen_string_literal: true

# Consumer Dashboard Controller
# Screen 1: Confidence Check - "Is my API working, fast, and not blocked?"
class Consumer::DashboardController < Consumer::ConsumerController
  def index
    @requests_24h = get_user_requests_24h
    @error_rate = calculate_user_error_rate
    @rate_limit_status = get_rate_limit_status
    @last_blocked = get_last_blocked_event
    @recent_activity = get_recent_activity(limit: 10)

    # Add environment and tier for display
    @environment = Rails.env.production? ? 'production' : 'test'
    @tier = current_user.tier.titleize
  end
end
