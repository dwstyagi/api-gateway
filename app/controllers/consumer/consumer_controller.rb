# frozen_string_literal: true

# Base controller for Consumer (Developer) Portal
# Provides authentication and helper methods for API consumers
class Consumer::ConsumerController < ApplicationController
  before_action :require_user
  before_action :require_non_admin_user

  private

  # Ensure only non-admin users can access the developer portal
  # Admins should use the admin dashboard at /dashboard
  def require_non_admin_user
    if current_user.admin?
      redirect_to dashboard_path, alert: "Admins should use the Admin Dashboard. Create a separate user account to test the developer experience."
    end
  end

  # Get user's requests in last 24 hours
  def get_user_requests_24h
    MetricsService.get_user_requests(current_user.id, window: :day)
  end

  # Calculate user's error rate
  def calculate_user_error_rate
    total = MetricsService.get_user_requests(current_user.id, window: :day)
    errors = MetricsService.get_user_errors(current_user.id, window: :day)

    return 0.0 if total.zero?
    ((errors.to_f / total) * 100).round(2)
  end

  # Get rate limit status for user's tier
  def get_rate_limit_status
    tier = current_user.tier
    policy = RateLimitPolicy.find_by(tier: tier, strategy: 'fixed_window') ||
             RateLimitPolicy.find_by(tier: tier)

    return { used: 0, limit: 0, percentage: 0, reset_at: nil } unless policy

    key = "rate_limit:user:#{current_user.id}:hour"
    used = $redis.get(key).to_i
    limit = policy.capacity
    percentage = limit.zero? ? 0 : ((used.to_f / limit) * 100).round(0)

    # Get TTL for reset time
    ttl = $redis.ttl(key)
    reset_at = ttl > 0 ? Time.current + ttl.seconds : nil

    {
      used: used,
      limit: limit,
      percentage: percentage,
      reset_at: reset_at,
      tier: tier,
      policy: policy
    }
  end

  # Get last blocked event for user
  def get_last_blocked_event
    AuditLog.where(actor_user_id: current_user.id)
            .where("event_type LIKE ?", "%block%")
            .or(AuditLog.where(actor_user_id: current_user.id, event_type: 'rate_limit.exceeded'))
            .order(timestamp: :desc)
            .first
  end

  # Get recent activity for user
  def get_recent_activity(limit: 10)
    AuditLog.where(actor_user_id: current_user.id)
            .order(timestamp: :desc)
            .limit(limit)
  end

  # Get requests per minute chart data (last 60 minutes)
  def get_requests_per_minute_chart
    data = {}
    60.downto(0) do |i|
      time = i.minutes.ago
      minute_key = time.strftime('%H:%M')
      redis_key = "metrics:user:#{current_user.id}:minute:#{time.to_i / 60}"
      data[minute_key] = $redis.get(redis_key).to_i
    end
    data
  end

  # Get top endpoints for user
  def get_top_endpoints(limit: 5)
    # Get all endpoint keys for this user
    pattern = "metrics:user:#{current_user.id}:endpoint:*:count"
    keys = $redis.keys(pattern)

    endpoints = keys.map do |key|
      endpoint = key.split(':')[4]
      count = $redis.get(key).to_i
      { endpoint: endpoint, count: count }
    end

    endpoints.sort_by { |e| -e[:count] }.take(limit)
  end

  # Get user errors with filters
  def get_user_errors(filter: 'all', limit: 50)
    logs = AuditLog.where(actor_user_id: current_user.id)

    case filter
    when '429'
      logs = logs.where("metadata->>'status_code' = ?", '429')
    when '401'
      logs = logs.where("metadata->>'status_code' = ?", '401')
    when '403'
      logs = logs.where("metadata->>'status_code' = ?", '403')
    when '5xx'
      logs = logs.where("(metadata->>'status_code')::int >= 500")
    end

    logs.order(timestamp: :desc).limit(limit)
  end

  # Generate error suggestion based on status code and context
  def generate_error_suggestion(status_code, metadata = {})
    case status_code.to_i
    when 429
      tier = current_user.tier
      next_tier = tier == 'free' ? 'Pro' : 'Enterprise'
      {
        reason: 'Rate limit exceeded',
        suggestion: "Reduce burst traffic or upgrade to #{next_tier} tier for higher limits",
        action: 'upgrade_tier',
        action_url: consumer_upgrade_path
      }
    when 401
      {
        reason: 'Invalid API key',
        suggestion: 'Check that your API key is active in the API Keys page',
        action: 'view_keys',
        action_url: consumer_api_keys_path
      }
    when 403
      if metadata['blocked_reason'] == 'insufficient_scope'
        {
          reason: 'Insufficient scope',
          suggestion: "Key needs '#{metadata['required_scope']}' scope",
          action: 'rotate_key',
          action_url: consumer_api_keys_path
        }
      elsif metadata['blocked_reason'] == 'ip_blocked'
        {
          reason: 'IP blocked by admin',
          suggestion: "Contact support with IP: #{metadata['ip_address']}",
          action: 'contact_support',
          action_url: '#'
        }
      else
        {
          reason: 'Access forbidden',
          suggestion: 'Check your API key permissions',
          action: 'view_keys',
          action_url: consumer_api_keys_path
        }
      end
    when 500..599
      {
        reason: 'Server error',
        suggestion: 'Issue on our end. Check status page or contact support if this persists.',
        action: 'status_page',
        action_url: '#'
      }
    else
      {
        reason: 'Request failed',
        suggestion: 'Check your request parameters and try again',
        action: nil,
        action_url: nil
      }
    end
  end
end
