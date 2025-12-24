# frozen_string_literal: true

# Admin Audit Logs Controller
#
# Endpoints for viewing audit logs:
# - List all audit logs with filtering
# - View specific audit log details
# - Export audit logs
# - Search audit logs
#
# All endpoints require admin authentication
class Admin::AuditLogsController < ApplicationController
  before_action :require_admin
  before_action :set_audit_log, only: [:show]

  # GET /admin/audit_logs
  # List all audit logs with extensive filtering
  def index
    logs = AuditLog.includes(:actor).all

    # Filter by event type
    logs = logs.where('event_type LIKE ?', "#{params[:event_type]}%") if params[:event_type].present?

    # Filter by category (admin, security, auth, etc.)
    if params[:category].present?
      logs = logs.where('event_type LIKE ?', "#{params[:category]}.%")
    end

    # Filter by user
    logs = logs.where(actor_user_id: params[:user_id]) if params[:user_id].present?

    # Filter by IP
    logs = logs.where(actor_ip: params[:actor_ip]) if params[:actor_ip].present?

    # Date range filtering
    if params[:start_date].present?
      begin
        start_date = DateTime.parse(params[:start_date])
        logs = logs.where('created_at >= ?', start_date)
      rescue ArgumentError
        # Invalid date, skip filter
      end
    end

    if params[:end_date].present?
      begin
        end_date = DateTime.parse(params[:end_date])
        logs = logs.where('created_at <= ?', end_date)
      rescue ArgumentError
        # Invalid date, skip filter
      end
    end

    # Search in metadata (JSON search)
    if params[:search].present?
      logs = logs.where("metadata::text ILIKE ?", "%#{params[:search]}%")
    end

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    per_page = [per_page, 100].min

    total = logs.count
    offset = (page - 1) * per_page

    logs = logs.order(created_at: :desc).limit(per_page).offset(offset)

    render json: {
      success: true,
      data: logs.map { |log| serialize_audit_log(log) },
      pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: (total.to_f / per_page).ceil
      }
    }
  end

  # GET /admin/audit_logs/:id
  # Get detailed audit log
  def show
    render json: {
      success: true,
      data: serialize_audit_log(@audit_log, detailed: true)
    }
  end

  # GET /admin/audit_logs/stats
  # Get audit log statistics
  def stats
    total_logs = AuditLog.count

    # Logs by category (extract first part of event_type)
    logs_by_category = AuditLog.select("SPLIT_PART(event_type, '.', 1) as category, COUNT(*) as count")
                               .group("SPLIT_PART(event_type, '.', 1)")
                               .order('count DESC')
                               .limit(10)
                               .map { |r| [r.category, r.count.to_i] }
                               .to_h

    # Recent logs count (last 24 hours)
    recent_logs = AuditLog.where('created_at > ?', 24.hours.ago).count

    # Security events count
    security_logs = AuditLog.where('event_type LIKE ?', 'security.%').count

    # Admin actions count
    admin_logs = AuditLog.where('event_type LIKE ?', 'admin.%').count

    # Most active users (by log count)
    top_users = AuditLog.where.not(actor_user_id: nil)
                        .group(:actor_user_id)
                        .select('actor_user_id, COUNT(*) as count')
                        .order('count DESC')
                        .limit(5)
                        .map do |record|
                          user = User.find_by(id: record.actor_user_id)
                          {
                            user_id: record.actor_user_id,
                            email: user&.email || 'Unknown',
                            count: record.count.to_i
                          }
                        end

    # Most active IPs
    top_ips = AuditLog.where.not(actor_ip: nil)
                      .group(:actor_ip)
                      .select('actor_ip, COUNT(*) as count')
                      .order('count DESC')
                      .limit(5)
                      .map { |r| { ip: r.actor_ip, count: r.count.to_i } }

    render json: {
      success: true,
      data: {
        total_logs: total_logs,
        recent_logs_24h: recent_logs,
        security_events: security_logs,
        admin_actions: admin_logs,
        by_category: logs_by_category,
        top_users: top_users,
        top_ips: top_ips
      }
    }
  end

  # GET /admin/audit_logs/event_types
  # Get all unique event types
  def event_types
    types = AuditLog.distinct.pluck(:event_type).sort

    # Group by category
    grouped = types.group_by { |type| type.split('.').first }

    render json: {
      success: true,
      data: {
        all: types,
        grouped: grouped,
        count: types.length
      }
    }
  end

  # GET /admin/audit_logs/export
  # Export audit logs as CSV
  def export
    logs = AuditLog.includes(:actor).order(created_at: :desc)

    # Apply same filters as index
    logs = logs.where('event_type LIKE ?', "#{params[:event_type]}%") if params[:event_type].present?
    logs = logs.where('event_type LIKE ?', "#{params[:category]}.%") if params[:category].present?
    logs = logs.where(actor_user_id: params[:user_id]) if params[:user_id].present?
    logs = logs.where(actor_ip: params[:actor_ip]) if params[:actor_ip].present?

    # Limit export to prevent memory issues
    logs = logs.limit(10000)

    csv_data = generate_csv(logs)

    send_data csv_data,
              filename: "audit_logs_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
              type: 'text/csv',
              disposition: 'attachment'
  end

  # GET /admin/audit_logs/timeline
  # Get timeline of events (for charts)
  def timeline
    # Default to last 7 days
    start_date = params[:start_date] ? DateTime.parse(params[:start_date]) : 7.days.ago
    end_date = params[:end_date] ? DateTime.parse(params[:end_date]) : Time.current

    # Group by day
    timeline_data = AuditLog.where(created_at: start_date..end_date)
                            .group("DATE(created_at)")
                            .select("DATE(created_at) as date, COUNT(*) as count")
                            .order('date ASC')
                            .map { |r| { date: r.date, count: r.count.to_i } }

    render json: {
      success: true,
      data: {
        timeline: timeline_data,
        start_date: start_date,
        end_date: end_date,
        total: timeline_data.sum { |d| d[:count] }
      }
    }
  rescue ArgumentError => e
    render json: {
      success: false,
      error: {
        code: 'INVALID_DATE',
        message: 'Invalid date format',
        details: e.message
      }
    }, status: :unprocessable_entity
  end

  private

  def set_audit_log
    @audit_log = AuditLog.includes(:actor).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: 'Audit log not found'
      }
    }, status: :not_found
  end

  def current_user
    request.env['current_user']
  end

  def require_admin
    unless current_user&.admin?
      render json: {
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: 'Admin access required'
        }
      }, status: :forbidden
    end
  end

  def serialize_audit_log(log, detailed: false)
    data = {
      id: log.id,
      event_type: log.event_type,
      actor_ip: log.actor_ip,
      metadata: log.metadata,
      created_at: log.created_at
    }

    if detailed && log.actor
      data[:user] = {
        id: log.actor.id,
        email: log.actor.email,
        role: log.actor.role
      }
    else
      data[:user_email] = log.actor&.email
    end

    data
  end

  def generate_csv(logs)
    require 'csv'

    CSV.generate(headers: true) do |csv|
      csv << ['ID', 'Event Type', 'User Email', 'Actor IP', 'Metadata', 'Created At']

      logs.each do |log|
        csv << [
          log.id,
          log.event_type,
          log.actor&.email || 'N/A',
          log.actor_ip,
          log.metadata.to_json,
          log.created_at.iso8601
        ]
      end
    end
  end
end
