# frozen_string_literal: true

# AdminMetricsChannel
# WebSocket channel for real-time admin metrics and alerts
#
# Broadcasts:
# - health_status: System health updates (gateway, redis, error rate, blocked IPs)
# - api_disabled: When an API is disabled
# - api_enabled: When an API is enabled
# - ip_blocked: When an IP is blocked
# - ip_unblocked: When an IP is unblocked
# - policy_created: When a rate limit policy is created
# - policy_updated: When a rate limit policy is updated
# - tier_changed: When a user's tier is changed
# - critical_event: When a critical security event occurs
class AdminMetricsChannel < ApplicationCable::Channel
  def subscribed
    # Only allow admin users to subscribe
    current_user = env['warden']&.user || reject
    reject unless current_user&.admin?

    stream_from 'admin:metrics'

    # Send current health status immediately on connection
    transmit({
      type: 'health_status',
      data: {
        gateway: check_gateway_health,
        redis: check_redis_health,
        database: check_database_health,
        error_rate: calculate_error_rate,
        blocked_ips: IpRule.blocked.active.count,
        timestamp: Time.current.iso8601
      }
    })
  end

  def unsubscribed
    stop_all_streams
  end

  # Client can request a health update
  def request_health_update
    transmit({
      type: 'health_status',
      data: {
        gateway: check_gateway_health,
        redis: check_redis_health,
        database: check_database_health,
        error_rate: calculate_error_rate,
        blocked_ips: IpRule.blocked.active.count,
        timestamp: Time.current.iso8601
      }
    })
  end

  private

  def check_gateway_health
    last_request_key = 'metrics:last_request_time'

    begin
      last_request_time = $redis.get(last_request_key)

      if last_request_time.nil?
        return 'warning'
      end

      last_request = Time.at(last_request_time.to_f)
      seconds_ago = (Time.current - last_request).to_i

      if seconds_ago < 60
        'healthy'
      elsif seconds_ago < 300
        'warning'
      else
        'critical'
      end
    rescue StandardError => e
      Rails.logger.error("Gateway health check failed: #{e.message}")
      'critical'
    end
  end

  def check_redis_health
    $redis.ping == 'PONG' ? 'healthy' : 'critical'
  rescue StandardError => e
    Rails.logger.error("Redis health check failed: #{e.message}")
    'critical'
  end

  def check_database_health
    ActiveRecord::Base.connection.active? ? 'healthy' : 'critical'
  rescue StandardError => e
    Rails.logger.error("Database health check failed: #{e.message}")
    'critical'
  end

  def calculate_error_rate
    begin
      error_count = MetricsService.get_counter('metrics:errors:5min') || 0
      total_requests = MetricsService.get_counter('metrics:requests:5min') || 0

      return 0.0 if total_requests.zero?

      ((error_count.to_f / total_requests.to_f) * 100).round(2)
    rescue StandardError => e
      Rails.logger.error("Error rate calculation failed: #{e.message}")
      0.0
    end
  end
end
