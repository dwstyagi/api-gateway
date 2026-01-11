# frozen_string_literal: true

# Health Check Controller
#
# Public endpoints for monitoring and load balancers
# - GET /health - Simple health check (returns 200 if all critical services are up)
# - GET /health/detailed - Detailed health check with dependency status and metrics

class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  # Simple health check for load balancers
  def show
    # Check if Redis and Database are accessible
    redis_status = check_redis
    database_status = check_database

    status_code = (redis_status && database_status) ? :ok : :service_unavailable

    render json: {
      status: status_code == :ok ? 'healthy' : 'unhealthy',
      timestamp: Time.current.iso8601,
      services: {
        redis: redis_status ? 'up' : 'down',
        database: database_status ? 'up' : 'down'
      }
    }, status: status_code
  end

  # Detailed health check with metrics and dependency status
  def detailed
    start_time = Time.current

    # Check all dependencies
    checks = {
      redis: check_redis_detailed,
      database: check_database_detailed,
      disk_space: check_disk_space,
      memory: check_memory
    }

    # Determine overall health
    all_healthy = checks.values.all? { |check| check[:status] == 'up' }
    status_code = all_healthy ? :ok : :service_unavailable

    # Get system metrics
    metrics = {
      uptime: get_uptime,
      request_stats: get_request_stats,
      error_rate: MetricsService.calculate_error_rate,
      throughput: MetricsService.calculate_throughput(:minute)
    }

    # Calculate check duration
    check_duration_ms = ((Time.current - start_time) * 1000).round(2)

    render json: {
      status: all_healthy ? 'healthy' : 'degraded',
      timestamp: Time.current.iso8601,
      version: '1.0.0',
      environment: Rails.env,
      checks: checks,
      metrics: metrics,
      check_duration_ms: check_duration_ms
    }, status: status_code
  end

  private

  # Simple Redis check
  def check_redis
    $redis.ping == 'PONG'
  rescue StandardError
    false
  end

  # Detailed Redis check
  def check_redis_detailed
    start = Time.current
    result = $redis.ping == 'PONG'
    duration = ((Time.current - start) * 1000).round(2)

    {
      status: result ? 'up' : 'down',
      response_time_ms: duration,
      info: result ? { connected_clients: $redis.info['connected_clients'] } : {}
    }
  rescue StandardError => e
    {
      status: 'down',
      error: e.message
    }
  end

  # Simple database check
  def check_database
    ActiveRecord::Base.connection.active?
  rescue StandardError
    false
  end

  # Detailed database check
  def check_database_detailed
    start = Time.current
    result = ActiveRecord::Base.connection.active?
    duration = ((Time.current - start) * 1000).round(2)

    if result
      pool_status = ActiveRecord::Base.connection_pool.stat
      {
        status: 'up',
        response_time_ms: duration,
        info: {
          connections: pool_status[:size],
          busy: pool_status[:busy],
          idle: pool_status[:idle]
        }
      }
    else
      { status: 'down' }
    end
  rescue StandardError => e
    {
      status: 'down',
      error: e.message
    }
  end

  # Check disk space
  def check_disk_space
    stat = `df -h / | tail -1`.split
    usage_percent = stat[4].to_i

    {
      status: usage_percent < 90 ? 'up' : 'warning',
      usage_percent: usage_percent,
      available: stat[3]
    }
  rescue StandardError => e
    {
      status: 'unknown',
      error: e.message
    }
  end

  # Check memory usage
  def check_memory
    if File.exist?('/proc/meminfo')
      meminfo = File.read('/proc/meminfo')
      total = meminfo[/MemTotal:\s+(\d+)/, 1].to_i
      available = meminfo[/MemAvailable:\s+(\d+)/, 1].to_i
      used_percent = ((total - available).to_f / total * 100).round(2)

      {
        status: used_percent < 90 ? 'up' : 'warning',
        used_percent: used_percent,
        total_mb: (total / 1024).round,
        available_mb: (available / 1024).round
      }
    else
      { status: 'unknown', message: 'Memory info not available' }
    end
  rescue StandardError => e
    {
      status: 'unknown',
      error: e.message
    }
  end

  # Get application uptime
  def get_uptime
    uptime_seconds = (Time.current - Rails.application.config.booted_at).to_i
    {
      seconds: uptime_seconds,
      human: distance_of_time(uptime_seconds)
    }
  rescue StandardError
    { seconds: 0, human: 'unknown' }
  end

  # Get request statistics
  def get_request_stats
    {
      total: MetricsService.get_request_stats[:total],
      last_minute: MetricsService.calculate_throughput(:minute).round(2)
    }
  rescue StandardError => e
    Rails.logger.error("Error getting request stats: #{e.message}")
    { error: 'Unable to fetch request stats' }
  end

  # Human readable time distance
  def distance_of_time(seconds)
    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      "#{(seconds / 60).round}m"
    elsif seconds < 86400
      "#{(seconds / 3600).round}h"
    else
      "#{(seconds / 86400).round}d"
    end
  end
end
