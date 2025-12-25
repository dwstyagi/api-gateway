# frozen_string_literal: true

# Audit Logs Channel
#
# Streams real-time audit logs to admin users
#
# Events:
# - audit_log_created: New audit log entry
#
# Subscription:
#   cable.subscriptions.create('AuditLogsChannel', {
#     received(data) {
#       console.log('Audit log:', data);
#     }
#   });
#
# Filtering:
#   cable.subscriptions.create(
#     { channel: 'AuditLogsChannel', event_type: 'api_key.created' },
#     { received(data) { ... } }
#   );
class AuditLogsChannel < ApplicationCable::Channel
  def subscribed
    # Only admins can subscribe to audit logs
    reject_unless_admin!

    if params[:event_type]
      # Subscribe to specific event type
      stream_from "audit_logs:#{params[:event_type]}"
      transmit({
        type: 'connected',
        message: "Subscribed to #{params[:event_type]} audit logs",
        timestamp: Time.current.iso8601
      })
    elsif params[:user_id]
      # Subscribe to specific user's actions
      stream_from "audit_logs:user:#{params[:user_id]}"
      transmit({
        type: 'connected',
        message: "Subscribed to user #{params[:user_id]} audit logs",
        timestamp: Time.current.iso8601
      })
    else
      # Subscribe to all audit logs
      stream_from 'audit_logs:global'
      transmit({
        type: 'connected',
        message: 'Subscribed to all audit logs',
        timestamp: Time.current.iso8601
      })
    end
  end

  def unsubscribed
    stop_all_streams
  end

  # Handle client messages
  def receive(data)
    case data['action']
    when 'filter_by_event_type'
      # Change filter to specific event type
      stop_all_streams
      stream_from "audit_logs:#{data['event_type']}"
      transmit({
        type: 'filter_changed',
        event_type: data['event_type']
      })

    when 'filter_by_user'
      # Change filter to specific user
      stop_all_streams
      stream_from "audit_logs:user:#{data['user_id']}"
      transmit({
        type: 'filter_changed',
        user_id: data['user_id']
      })

    when 'show_all'
      # Show all audit logs
      stop_all_streams
      stream_from 'audit_logs:global'
      transmit({
        type: 'filter_changed',
        message: 'Showing all audit logs'
      })

    else
      transmit({
        type: 'error',
        message: "Unknown action: #{data['action']}"
      })
    end
  end
end
