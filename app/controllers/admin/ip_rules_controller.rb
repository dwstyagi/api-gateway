# frozen_string_literal: true

# IP Rules Management Controller
#
# Admin endpoints for managing IP-based access control:
# - List blocked/allowed IPs
# - Manually block/unblock IPs
# - View auto-blocked IPs
# - View violation statistics
#
# All endpoints require admin authentication
class Admin::IpRulesController < ApplicationController
  before_action :require_admin
  before_action :set_ip_rule, only: [:show, :update, :destroy]

  # GET /admin/ip_rules
  # List all IP rules with filtering
  def index
    rules = IpRule.all

    # Filter by rule type
    rules = rules.where(rule_type: params[:rule_type]) if params[:rule_type].present?

    # Filter by auto-blocked
    rules = rules.auto_blocked if params[:auto_blocked] == 'true'
    rules = rules.manual if params[:auto_blocked] == 'false'

    # Filter by active/expired
    rules = rules.active if params[:status] == 'active'
    rules = rules.expired if params[:status] == 'expired'

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    per_page = [per_page, 100].min # Max 100 per page

    total = rules.count
    offset = (page - 1) * per_page

    rules = rules.order(created_at: :desc).limit(per_page).offset(offset)

    render json: {
      success: true,
      data: rules.map { |rule| serialize_rule(rule) },
      pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: (total.to_f / per_page).ceil
      }
    }
  end

  # GET /admin/ip_rules/:id
  # Get details for a specific IP rule
  def show
    render json: {
      success: true,
      data: serialize_rule(@ip_rule)
    }
  end

  # POST /admin/ip_rules
  # Manually create a block or allow rule
  def create
    rule = IpRule.new(ip_rule_params)
    rule.auto_blocked = false # Manual rule

    if rule.save
      log_admin_action('ip_rule_created', rule)

      render json: {
        success: true,
        message: "IP #{rule.rule_type} rule created successfully",
        data: serialize_rule(rule)
      }, status: :created
    else
      render json: {
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Failed to create IP rule',
          details: rule.errors.full_messages
        }
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /admin/ip_rules/:id
  # Update an IP rule (reason, expiration, etc.)
  def update
    if @ip_rule.update(ip_rule_params)
      log_admin_action('ip_rule_updated', @ip_rule)

      render json: {
        success: true,
        message: 'IP rule updated successfully',
        data: serialize_rule(@ip_rule)
      }
    else
      render json: {
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Failed to update IP rule',
          details: @ip_rule.errors.full_messages
        }
      }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/ip_rules/:id
  # Remove an IP rule
  def destroy
    ip_address = @ip_rule.ip_address
    @ip_rule.destroy

    log_admin_action('ip_rule_deleted', { ip_address: ip_address })

    render json: {
      success: true,
      message: 'IP rule deleted successfully'
    }
  end

  # POST /admin/ip_rules/block
  # Manually block an IP address
  def block_ip
    ip_address = params[:ip_address]
    reason = params[:reason] || 'Manually blocked by admin'
    duration = params[:duration]&.to_i # Optional, in seconds

    unless valid_ip?(ip_address)
      return render json: {
        success: false,
        error: {
          code: 'INVALID_IP',
          message: 'Invalid IP address format'
        }
      }, status: :unprocessable_entity
    end

    expires_at = duration ? Time.current + duration.seconds : nil

    rule = IpRule.create!(
      ip_address: ip_address,
      rule_type: 'block',
      reason: reason,
      auto_blocked: false,
      expires_at: expires_at
    )

    log_admin_action('ip_blocked', rule)

    render json: {
      success: true,
      message: "IP #{ip_address} blocked successfully",
      data: serialize_rule(rule)
    }, status: :created
  end

  # POST /admin/ip_rules/unblock
  # Unblock an IP address
  def unblock_ip
    ip_address = params[:ip_address]

    unless valid_ip?(ip_address)
      return render json: {
        success: false,
        error: {
          code: 'INVALID_IP',
          message: 'Invalid IP address format'
        }
      }, status: :unprocessable_entity
    end

    # Unblock from Redis if AutoBlockerService is available
    if defined?(AutoBlockerService)
      AutoBlockerService.unblock_ip(ip_address) rescue nil
    end

    # Remove from database
    IpRule.where(ip_address: ip_address, rule_type: 'block').destroy_all

    log_admin_action('ip_unblocked', { ip_address: ip_address })

    render json: {
      success: true,
      message: "IP #{ip_address} unblocked successfully"
    }
  end

  # GET /admin/ip_rules/blocked
  # List all currently blocked IPs (from Redis + DB)
  def blocked_ips
    # Get from Redis (includes auto-blocked) if AutoBlockerService is available
    redis_blocked = if defined?(AutoBlockerService)
                      AutoBlockerService.blocked_ips rescue []
                    else
                      []
                    end

    # Get from database
    db_blocked = IpRule.blocked.active.pluck(:ip_address)

    # Merge and deduplicate
    all_blocked = (redis_blocked + db_blocked).uniq

    # Get details for each
    details = all_blocked.map do |ip|
      rule = IpRule.blocked.active.find_by(ip_address: ip)
      {
        ip_address: ip,
        reason: rule&.reason,
        auto_blocked: rule&.auto_blocked || false,
        expires_at: rule&.expires_at,
        created_at: rule&.created_at
      }
    end

    render json: {
      success: true,
      data: details,
      count: all_blocked.length
    }
  end

  # GET /admin/ip_rules/violations/:ip
  # Get violation statistics for an IP
  def violations
    ip_address = params[:ip]

    unless valid_ip?(ip_address)
      return render json: {
        success: false,
        error: {
          code: 'INVALID_IP',
          message: 'Invalid IP address format'
        }
      }, status: :unprocessable_entity
    end

    violations = {}

    # Only get violations if AutoBlockerService is available
    if defined?(AutoBlockerService) && defined?(AutoBlockerService::THRESHOLDS)
      begin
        AutoBlockerService::THRESHOLDS.keys.each do |violation_type|
          count = AutoBlockerService.violation_count(ip_address, violation_type)
          threshold = AutoBlockerService::THRESHOLDS[violation_type]

          violations[violation_type] = {
            count: count,
            threshold: threshold[:limit],
            window_seconds: threshold[:window],
            block_duration: threshold[:block_duration],
            percentage: (count.to_f / threshold[:limit] * 100).round(2)
          }
        end
      rescue => e
        violations = { error: 'AutoBlockerService not fully configured' }
      end
    end

    whitelisted = defined?(AutoBlockerService) ? (AutoBlockerService.whitelisted?(ip_address) rescue false) : false
    blocked = IpRule.blocked?(ip_address)

    render json: {
      success: true,
      data: {
        ip_address: ip_address,
        whitelisted: whitelisted,
        blocked: blocked,
        violations: violations
      }
    }
  end

  # POST /admin/ip_rules/clear_violations
  # Clear violation counters for an IP
  def clear_violations
    ip_address = params[:ip_address]

    unless valid_ip?(ip_address)
      return render json: {
        success: false,
        error: {
          code: 'INVALID_IP',
          message: 'Invalid IP address format'
        }
      }, status: :unprocessable_entity
    end

    # Clear violations if AutoBlockerService is available
    if defined?(AutoBlockerService)
      AutoBlockerService.clear_violations(ip_address) rescue nil
    end

    log_admin_action('violations_cleared', { ip_address: ip_address })

    render json: {
      success: true,
      message: "Violations cleared for IP #{ip_address}"
    }
  end

  private

  def set_ip_rule
    @ip_rule = IpRule.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: 'IP rule not found'
      }
    }, status: :not_found
  end

  def ip_rule_params
    params.require(:ip_rule).permit(
      :ip_address,
      :rule_type,
      :reason,
      :expires_at
    )
  end

  def require_admin
    current_user = request.env['current_user']

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

  def valid_ip?(ip)
    # Basic IP validation (IPv4 and IPv6)
    ip.match?(/\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z/) ||
      ip.match?(/\A([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}\z/)
  end

  def serialize_rule(rule)
    {
      id: rule.id,
      ip_address: rule.ip_address,
      rule_type: rule.rule_type,
      reason: rule.reason,
      auto_blocked: rule.auto_blocked,
      expires_at: rule.expires_at,
      active: rule.active?,
      created_at: rule.created_at,
      updated_at: rule.updated_at
    }
  end

  def log_admin_action(action, details)
    AuditLog.create(
      event_type: "admin.#{action}",
      actor_user_id: request.env['current_user']&.id,
      actor_ip: request.ip,
      metadata: details.is_a?(Hash) ? details : { id: details.id }
    )
  end
end
