# frozen_string_literal: true

# Admin Overview Controller
# READ-ONLY system health dashboard
# Purpose: "Are we about to go down?"
#
# Shows 4 critical signals:
# - Gateway Status
# - Redis Status
# - Error Rate
# - Blocked IPs
#
# Plus last 10 critical events (admin.* and security.* types)
class Admin::OverviewController < AdminController

  def index
    @health = {
      gateway: check_gateway_health,
      redis: check_redis_health,
      database: check_database_health,
      error_rate: calculate_error_rate,
      blocked_ips: IpRule.blocked.active.count
    }

    @critical_events = AuditLog
                       .where("event_type LIKE 'admin.%' OR event_type LIKE 'security.%'")
                       .order(created_at: :desc)
                       .limit(10)
                       .includes(:actor)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          success: true,
          health: @health,
          critical_events: @critical_events.map { |event| serialize_event(event) }
        }
      end
    end
  end

  def serialize_event(event)
    {
      id: event.id,
      timestamp: event.timestamp,
      event_type: event.event_type,
      actor: event.actor&.email,
      metadata: event.metadata
    }
  end

  private

  def check_gateway_health
    # Check if requests have been processed recently
    last_request_key = 'metrics:last_request_time'

    begin
      last_request_time = $redis.get(last_request_key)

      if last_request_time.nil?
        return 'warning' # No requests tracked yet
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
      # Get error count and total requests from metrics service
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
