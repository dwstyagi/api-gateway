# frozen_string_literal: true

# Metrics Channel
#
# Streams real-time metrics to admin users
#
# Events:
# - throughput_update: Current requests per second
# - error_rate_update: Current error rate
# - request_logged: Individual request logged
# - performance_update: Response time metrics
# - alert: System alerts
#
# Subscription:
#   cable.subscriptions.create('MetricsChannel', {
#     received(data) {
#       console.log('Metric update:', data);
#     }
#   });
class MetricsChannel < ApplicationCable::Channel
  def subscribed
    # Only admins can subscribe to system metrics
    reject_unless_admin!

    # Stream all metrics to this admin
    stream_from 'metrics:global'

    # Send initial state
    transmit({
      type: 'connected',
      message: 'Connected to metrics stream',
      timestamp: Time.current.iso8601
    })

    # Optionally start periodic updates
    start_periodic_updates if params[:periodic_updates]
  end

  def unsubscribed
    stop_all_streams
    stop_periodic_updates
  end

  # Handle client messages
  def receive(data)
    case data['action']
    when 'subscribe_endpoint'
      # Subscribe to specific endpoint metrics
      endpoint = data['endpoint']
      stream_from "metrics:endpoint:#{endpoint}"
      transmit({
        type: 'subscribed',
        endpoint: endpoint,
        message: "Subscribed to #{endpoint} metrics"
      })

    when 'get_current_stats'
      # Send current stats immediately
      send_current_stats

    when 'start_periodic_updates'
      start_periodic_updates

    when 'stop_periodic_updates'
      stop_periodic_updates

    else
      transmit({
        type: 'error',
        message: "Unknown action: #{data['action']}"
      })
    end
  end

  private

  # Send current statistics to client
  def send_current_stats
    stats = {
      type: 'current_stats',
      data: {
        throughput: MetricsService.calculate_throughput(:minute).round(2),
        error_rate: MetricsService.calculate_error_rate,
        total_requests: MetricsService.get_counter('requests:total'),
        total_errors: MetricsService.get_counter('errors:total'),
        performance: MetricsService.get_performance_stats(endpoint: nil)
      },
      timestamp: Time.current.iso8601
    }

    transmit(stats)
  rescue StandardError => e
    transmit({
      type: 'error',
      message: "Failed to fetch stats: #{e.message}"
    })
  end

  # Start sending periodic updates
  def start_periodic_updates
    return if @periodic_timer

    @periodic_timer = Concurrent::TimerTask.new(execution_interval: 2) do
      send_current_stats
    end

    @periodic_timer.execute
  end

  # Stop periodic updates
  def stop_periodic_updates
    return unless @periodic_timer

    @periodic_timer.shutdown
    @periodic_timer = nil
  end
end
