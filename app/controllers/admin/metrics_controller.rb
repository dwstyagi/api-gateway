# frozen_string_literal: true

module Admin
  # Metrics Controller
  #
  # Provides access to system metrics and observability data
  # Requires admin authentication
  class MetricsController < ApplicationController
    before_action :require_admin

    # GET /admin/metrics
    # Get comprehensive system metrics
    def index
      render json: {
        success: true,
        data: {
          requests: request_metrics,
          errors: error_metrics,
          performance: performance_metrics,
          system: system_metrics
        },
        timestamp: Time.current.iso8601
      }
    end

    # GET /admin/metrics/requests
    # Get detailed request metrics
    def requests
      window = params[:window]&.to_sym || :hour

      render json: {
        success: true,
        data: MetricsService.get_request_stats(window: window),
        window: window,
        timestamp: Time.current.iso8601
      }
    end

    # GET /admin/metrics/errors
    # Get error statistics
    def errors
      render json: {
        success: true,
        data: MetricsService.get_error_stats,
        timestamp: Time.current.iso8601
      }
    end

    # GET /admin/metrics/performance
    # Get performance statistics
    def performance
      endpoint = params[:endpoint]

      render json: {
        success: true,
        data: MetricsService.get_performance_stats(endpoint: endpoint),
        endpoint: endpoint || 'global',
        timestamp: Time.current.iso8601
      }
    end

    # GET /admin/metrics/throughput
    # Get throughput statistics
    def throughput
      windows = [:minute, :hour, :day]
      throughput_data = windows.each_with_object({}) do |window, hash|
        hash[window] = MetricsService.calculate_throughput(window)
      end

      render json: {
        success: true,
        data: throughput_data,
        timestamp: Time.current.iso8601
      }
    end

    # GET /admin/metrics/timeseries
    # Get time-series data for charting
    def timeseries
      metric_type = params[:type] || 'requests'
      window = params[:window]&.to_sym || :hour

      data = case metric_type
             when 'requests'
               get_requests_timeseries(window)
             when 'errors'
               get_errors_timeseries(window)
             when 'response_times'
               get_response_times_timeseries(window)
             else
               []
             end

      render json: {
        success: true,
        data: data,
        type: metric_type,
        window: window,
        timestamp: Time.current.iso8601
      }
    end

    # POST /admin/metrics/reset
    # Reset all metrics (useful for testing)
    def reset
      if Rails.env.production?
        render json: {
          success: false,
          error: {
            code: 'FORBIDDEN',
            message: 'Cannot reset metrics in production'
          }
        }, status: :forbidden
        return
      end

      MetricsService.reset_all!

      render json: {
        success: true,
        message: 'All metrics have been reset',
        timestamp: Time.current.iso8601
      }
    end

    private

    # Get request metrics summary
    def request_metrics
      {
        total: MetricsService.get_counter('requests:total'),
        throughput_per_second: MetricsService.calculate_throughput(:minute).round(2),
        by_status: MetricsService.get_request_stats[:by_status]
      }
    end

    # Get error metrics summary
    def error_metrics
      {
        total: MetricsService.get_counter('errors:total'),
        error_rate: MetricsService.calculate_error_rate,
        by_type: MetricsService.get_error_stats[:by_type]
      }
    end

    # Get performance metrics summary
    def performance_metrics
      global_stats = MetricsService.get_performance_stats(endpoint: nil)

      if global_stats.present?
        {
          avg_response_time_ms: global_stats[:avg]&.round(2),
          p95_response_time_ms: global_stats[:p95]&.round(2),
          p99_response_time_ms: global_stats[:p99]&.round(2)
        }
      else
        {
          avg_response_time_ms: 0,
          p95_response_time_ms: 0,
          p99_response_time_ms: 0
        }
      end
    end

    # Get system metrics summary
    def system_metrics
      {
        uptime_seconds: (Time.current - Rails.application.config.booted_at).to_i,
        environment: Rails.env,
        redis_connected: check_redis,
        database_connected: check_database
      }
    end

    # Get time-series data for requests
    def get_requests_timeseries(window)
      # Get all time buckets from Redis
      pattern = "timeseries:requests:#{window}:*"
      keys = $redis.keys(pattern).sort

      keys.map do |key|
        timestamp = key.split(':').last.to_i
        count = $redis.hgetall(key).values.map(&:to_i).sum

        {
          timestamp: timestamp,
          time: Time.at(timestamp).iso8601,
          value: count
        }
      end
    end

    # Get time-series data for errors
    def get_errors_timeseries(window)
      # Simplified - in production you'd store this in Redis
      [
        {
          timestamp: Time.current.to_i - 3600,
          time: 1.hour.ago.iso8601,
          value: MetricsService.get_counter('errors:total')
        }
      ]
    end

    # Get time-series data for response times
    def get_response_times_timeseries(window)
      # Simplified - in production you'd store this in Redis
      stats = MetricsService.get_performance_stats(endpoint: nil)

      return [] if stats.empty?

      [
        {
          timestamp: Time.current.to_i,
          time: Time.current.iso8601,
          avg: stats[:avg]&.round(2),
          p95: stats[:p95]&.round(2),
          p99: stats[:p99]&.round(2)
        }
      ]
    end

    # Check Redis connectivity
    def check_redis
      $redis.ping == 'PONG'
    rescue StandardError
      false
    end

    # Check database connectivity
    def check_database
      ActiveRecord::Base.connection.active?
    rescue StandardError
      false
    end
  end
end
