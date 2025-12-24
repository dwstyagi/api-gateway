# frozen_string_literal: true

# IpRulesMiddleware enforces IP-based access control
# Runs after RequestParserMiddleware, before Authentication
# Responsibilities:
# - Check if IP is blocked
# - Check if IP is allowlisted
# - Handle auto-blocking logic
# - Log IP rule violations
class IpRulesMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    client_ip = env['gateway.client_ip']

    # Check if IP is blocked
    if ip_blocked?(client_ip)
      return blocked_response(client_ip)
    end

    # Check allowlist (if configured)
    # If allowlist exists and IP is not in it, block
    if allowlist_enabled? && !ip_allowed?(client_ip)
      return not_allowed_response(client_ip)
    end

    @app.call(env)
  end

  private

  def ip_blocked?(ip)
    # Check Redis cache first for performance
    cached = $redis.get("blocked_ip:#{ip}")
    return cached == '1' if cached.present?

    # Check database
    rule = IpRule.where(rule_type: 'block')
                 .where('ip_address = ? OR ip_address = ?', ip, '*')
                 .where('expires_at IS NULL OR expires_at > ?', Time.current)
                 .first

    if rule
      # Cache the block status
      ttl = rule.expires_at ? (rule.expires_at.to_i - Time.current.to_i) : 3600
      $redis.setex("blocked_ip:#{ip}", ttl, '1')
      true
    else
      # Cache negative result briefly
      $redis.setex("blocked_ip:#{ip}", 60, '0')
      false
    end
  end

  def ip_allowed?(ip)
    # Check if there's an allowlist entry for this IP
    $redis.sismember('allowlist:ips', ip) ||
      IpRule.where(rule_type: 'allow', ip_address: ip).exists?
  end

  def allowlist_enabled?
    # Check if allowlist mode is enabled
    $redis.get('ip_rules:allowlist_mode') == '1'
  end

  def blocked_response(ip)
    # Get block reason if available
    rule = IpRule.find_by(rule_type: 'block', ip_address: ip)
    reason = rule&.reason || 'IP address is blocked'

    Rails.logger.warn("Blocked request from IP: #{ip} - #{reason}")

    # Log to audit
    AuditLog.create(
      event_type: 'security.ip_blocked',
      actor_ip: ip,
      metadata: {
        reason: reason,
        auto_blocked: rule&.auto_blocked || false
      }
    )

    [
      403,
      { 'Content-Type' => 'application/json' },
      [{
        success: false,
        error: {
          code: 'IP_BLOCKED',
          message: 'Your IP address has been blocked',
          details: { reason: reason }
        }
      }.to_json]
    ]
  end

  def not_allowed_response(ip)
    Rails.logger.warn("Request from non-allowlisted IP: #{ip}")

    [
      403,
      { 'Content-Type' => 'application/json' },
      [{
        success: false,
        error: {
          code: 'IP_NOT_ALLOWED',
          message: 'Your IP address is not allowlisted'
        }
      }.to_json]
    ]
  end
end
