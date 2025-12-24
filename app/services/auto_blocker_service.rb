# frozen_string_literal: true

# AutoBlockerService detects abuse patterns and automatically blocks malicious IPs
#
# Detection Rules:
# 1. Invalid API Key Flood: 10+ invalid keys in 1 minute → 1 hour block
# 2. Invalid JWT Flood: 20+ invalid JWTs in 1 minute → 1 hour block
# 3. Rate Limit Abuse: 50+ rate limit hits in 5 minutes → 30 minute block
# 4. Authentication Spam: 30+ failed auth attempts in 5 minutes → 2 hour block
#
# Uses Redis for violation tracking with automatic expiration (TTL)
# Logs all auto-blocks to AuditLog for security monitoring
class AutoBlockerService
  # Violation thresholds
  THRESHOLDS = {
    invalid_api_key: { limit: 10, window: 60, block_duration: 3600 },      # 10 in 1min → 1hr
    invalid_jwt: { limit: 20, window: 60, block_duration: 3600 },          # 20 in 1min → 1hr
    rate_limit_abuse: { limit: 50, window: 300, block_duration: 1800 },    # 50 in 5min → 30min
    auth_failure: { limit: 30, window: 300, block_duration: 7200 }         # 30 in 5min → 2hr
  }.freeze

  class << self
    # Record a violation and auto-block if threshold exceeded
    #
    # @param ip [String] Client IP address
    # @param violation_type [Symbol] Type of violation (:invalid_api_key, :invalid_jwt, etc.)
    # @return [Boolean] true if IP was auto-blocked
    def record_violation(ip, violation_type)
      return false if whitelisted?(ip)
      return false unless THRESHOLDS.key?(violation_type)

      threshold = THRESHOLDS[violation_type]
      violation_count = increment_violation(ip, violation_type, threshold[:window])

      if violation_count >= threshold[:limit]
        auto_block_ip(ip, violation_type, threshold[:block_duration])
        true
      else
        false
      end
    rescue Redis::BaseError => e
      Rails.logger.error("AutoBlocker Redis error: #{e.message}")
      false # Fail-open on Redis errors
    end

    # Record invalid API key attempt
    def record_invalid_api_key(ip)
      record_violation(ip, :invalid_api_key)
    end

    # Record invalid JWT attempt
    def record_invalid_jwt(ip)
      record_violation(ip, :invalid_jwt)
    end

    # Record rate limit hit
    def record_rate_limit_abuse(ip)
      record_violation(ip, :rate_limit_abuse)
    end

    # Record failed authentication
    def record_auth_failure(ip)
      record_violation(ip, :auth_failure)
    end

    # Check if IP is whitelisted (bypass auto-blocking)
    def whitelisted?(ip)
      # Check localhost
      return true if ['127.0.0.1', '::1', 'localhost'].include?(ip)

      # Check database allowlist
      IpRule.allowed?(ip)
    end

    # Get current violation count for IP and type
    def violation_count(ip, violation_type)
      key = violation_key(ip, violation_type)
      $redis.get(key).to_i
    end

    # Clear violations for IP (used after successful auth or manual intervention)
    def clear_violations(ip)
      THRESHOLDS.keys.each do |violation_type|
        key = violation_key(ip, violation_type)
        $redis.del(key)
      end
    end

    # Get all currently blocked IPs (from Redis)
    def blocked_ips
      keys = $redis.keys('blocked_ip:*')
      keys.map { |key| key.sub('blocked_ip:', '') }
    end

    # Manually unblock an IP
    def unblock_ip(ip)
      # Remove from Redis cache
      $redis.del("blocked_ip:#{ip}")

      # Expire database rules
      IpRule.where(ip_address: ip, rule_type: 'block')
             .where('expires_at > ?', Time.current)
             .update_all(expires_at: Time.current)

      # Clear violation counters
      clear_violations(ip)

      Rails.logger.info("IP manually unblocked: #{ip}")
    end

    private

    # Increment violation counter and return new count
    def increment_violation(ip, violation_type, window)
      key = violation_key(ip, violation_type)
      count = $redis.incr(key)

      # Set expiration on first violation
      $redis.expire(key, window) if count == 1

      count
    end

    # Auto-block IP and log to audit
    def auto_block_ip(ip, violation_type, duration)
      reason = "Auto-blocked: #{violation_type.to_s.humanize} threshold exceeded"

      # Create database record
      IpRule.auto_block!(ip, reason: reason, duration: duration)

      # Log to audit
      AuditLog.create(
        event_type: 'security.auto_block',
        actor_ip: ip,
        metadata: {
          violation_type: violation_type,
          duration: duration,
          reason: reason,
          auto_blocked: true
        }
      )

      # Send alert (hook for Slack/Email integration)
      send_alert(ip, violation_type, duration)

      Rails.logger.warn("Auto-blocked IP: #{ip} for #{violation_type} (#{duration}s)")
    end

    # Generate Redis key for violation tracking
    def violation_key(ip, violation_type)
      "violations:#{violation_type}:#{ip}"
    end

    # Send alert notification (implement integration here)
    def send_alert(ip, violation_type, duration)
      # TODO: Integrate with Slack/Email/PagerDuty
      # For now, just log
      Rails.logger.warn("[SECURITY ALERT] IP auto-blocked: #{ip}, reason: #{violation_type}, duration: #{duration}s")

      # Example Slack integration (uncomment and configure):
      # if ENV['SLACK_WEBHOOK_URL'].present?
      #   HTTParty.post(ENV['SLACK_WEBHOOK_URL'], {
      #     body: {
      #       text: "🚨 Security Alert: IP #{ip} auto-blocked for #{violation_type}"
      #     }.to_json,
      #     headers: { 'Content-Type' => 'application/json' }
      #   })
      # end
    end
  end
end
