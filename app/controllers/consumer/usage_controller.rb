# frozen_string_literal: true

# Consumer Usage Controller
# Screen 3: Usage & Rate Limits - "Will I get blocked today?"
class Consumer::UsageController < Consumer::ConsumerController
  def index
    @requests_per_minute = get_requests_per_minute_chart
    @rate_limit_status = get_rate_limit_status
    @top_endpoints = get_top_endpoints(limit: 5)
    @tier_info = {
      current: current_user.tier,
      display_name: current_user.tier.titleize,
      can_upgrade: current_user.tier != 'enterprise'
    }

    # Calculate total for percentage bars
    total_requests = @top_endpoints.sum { |e| e[:count] }
    @top_endpoints.each do |endpoint|
      endpoint[:percentage] = total_requests.zero? ? 0 : ((endpoint[:count].to_f / total_requests) * 100).round(0)
    end
  end
end
