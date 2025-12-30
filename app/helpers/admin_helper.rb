# frozen_string_literal: true

# AdminHelper
# Helper methods for admin UI - blast radius calculations, status badges, etc.
module AdminHelper
  # Calculate blast radius for API definition changes
  # Returns hash with affected_users, active_keys, requests_per_hour
  def calculate_api_blast_radius(api_definition)
    # Count users with active API keys
    user_count = User.joins(:api_keys)
                     .where(api_keys: { status: 'active' })
                     .distinct
                     .count

    # Count active API keys
    key_count = ApiKey.where(status: 'active').count

    # Get hourly request metrics from Redis
    metric_key = "api:#{api_definition.id}:requests:hour"
    hourly_requests = begin
      MetricsService.get_counter(metric_key) || 0
    rescue StandardError
      0
    end

    {
      affected_users: user_count,
      active_keys: key_count,
      requests_per_hour: hourly_requests
    }
  end

  # Calculate blast radius for rate limit policy changes
  # Returns hash with affected_users, active_keys, api_name
  def calculate_policy_blast_radius(tier, api_definition_id)
    # Get API definition
    api_definition = ApiDefinition.find_by(id: api_definition_id)

    # Count users in the affected tier(s)
    # If tier is nil, affects all tiers
    tiers = tier.present? ? [tier] : %w[free pro enterprise]
    user_count = User.where(tier: tiers).count

    # Count active API keys for users in the affected tier(s)
    key_count = ApiKey.active
                      .joins(:user)
                      .where(users: { tier: tiers })
                      .count

    {
      affected_users: user_count,
      active_keys: key_count,
      api_name: api_definition&.name || 'Unknown'
    }
  end

  # Calculate blast radius for user tier changes
  # Returns hash with active_keys count for that user
  def calculate_user_blast_radius(user)
    {
      active_keys: user.api_keys.where(status: 'active').count,
      email: user.email,
      current_tier: user.tier
    }
  end

  # Render status badge with appropriate DaisyUI styling
  # status: 'active', 'enabled', 'disabled', 'deprecated', 'blocked', 'revoked'
  def status_badge(status)
    colors = {
      'active' => 'badge-success',
      'enabled' => 'badge-success',
      'disabled' => 'badge-error',
      'deprecated' => 'badge-warning',
      'blocked' => 'badge-error',
      'revoked' => 'badge-ghost',
      'expired' => 'badge-ghost'
    }

    badge_class = colors[status.to_s] || 'badge-ghost'

    content_tag :span, status.titleize, class: "badge #{badge_class}"
  end

  # Format countdown timer for expiring IP blocks
  # Returns "2h 34m 12s" or "Expired" or "Never"
  def countdown_timer(expires_at)
    return 'Never' unless expires_at

    seconds = (expires_at - Time.current).to_i
    return 'Expired' if seconds <= 0

    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    "#{hours}h #{minutes}m #{secs}s"
  end

  # Render AUTO vs MANUAL badge for IP rules
  def auto_manual_badge(auto_blocked)
    if auto_blocked
      content_tag :span, 'AUTO', class: 'badge badge-sm badge-ghost'
    else
      content_tag :span, 'MANUAL', class: 'badge badge-sm badge-info'
    end
  end

  # Format time ago for admin screens (more precise than time_ago_in_words)
  def admin_time_ago(time)
    return 'Never' unless time

    seconds = (Time.current - time).to_i

    if seconds < 60
      "#{seconds}s ago"
    elsif seconds < 3600
      "#{seconds / 60}m ago"
    elsif seconds < 86400
      "#{seconds / 3600}h ago"
    else
      "#{seconds / 86400}d ago"
    end
  end

  # Render health status indicator (colored dot + text)
  def health_status_indicator(status)
    case status.to_s
    when 'healthy', 'connected'
      content_tag :div, class: 'flex items-center' do
        concat content_tag(:div, '', class: 'w-3 h-3 rounded-full bg-green-500 mr-2')
        concat content_tag(:span, 'Healthy', class: 'text-sm font-medium text-green-700')
      end
    when 'warning', 'degraded'
      content_tag :div, class: 'flex items-center' do
        concat content_tag(:div, '', class: 'w-3 h-3 rounded-full bg-yellow-500 mr-2')
        concat content_tag(:span, 'Warning', class: 'text-sm font-medium text-yellow-700')
      end
    when 'critical', 'down', 'disconnected'
      content_tag :div, class: 'flex items-center' do
        concat content_tag(:div, '', class: 'w-3 h-3 rounded-full bg-red-600 mr-2')
        concat content_tag(:span, 'Critical', class: 'text-sm font-medium text-red-700')
      end
    else
      content_tag :div, class: 'flex items-center' do
        concat content_tag(:div, '', class: 'w-3 h-3 rounded-full bg-gray-400 mr-2')
        concat content_tag(:span, 'Unknown', class: 'text-sm font-medium text-gray-700')
      end
    end
  end

  # Format error rate with color coding
  def format_error_rate(error_rate)
    rate = error_rate.to_f

    color_class = if rate > 5
                    'text-red-600 font-bold'
                  elsif rate > 1
                    'text-yellow-600 font-semibold'
                  else
                    'text-green-600'
                  end

    content_tag :span, "#{rate.round(2)}%", class: color_class
  end

  # Render strategy description for rate limit policies
  def strategy_description(strategy)
    descriptions = {
      'token_bucket' => 'Allows burst traffic, tokens refill at constant rate',
      'fixed_window' => 'Simple counter that resets at fixed intervals',
      'sliding_window' => 'Smooth rate limiting with weighted time window',
      'leaky_bucket' => 'Constant drain rate, strict rate control',
      'concurrency' => 'Limits simultaneous requests to backend'
    }

    descriptions[strategy] || 'Unknown strategy'
  end

  # Get badge class for rate limit strategy
  def strategy_badge_class(strategy)
    case strategy
    when 'token_bucket'
      'badge-primary'
    when 'fixed_window'
      'badge-secondary'
    when 'sliding_window'
      'badge-accent'
    when 'leaky_bucket'
      'badge-info'
    when 'concurrency'
      'badge-warning'
    else
      'badge-ghost'
    end
  end

  # Format large numbers with delimiters
  def format_count(count)
    number_with_delimiter(count || 0)
  end

  # Render tier badge
  def tier_badge(tier)
    colors = {
      'free' => 'badge-ghost',
      'pro' => 'badge-info',
      'enterprise' => 'badge-success'
    }

    badge_class = colors[tier.to_s.downcase] || 'badge-ghost'

    content_tag :span, tier.titleize, class: "badge #{badge_class} badge-sm"
  end

  # Render role badge
  def role_badge(role)
    badge_class = role.to_s == 'admin' ? 'badge-error' : 'badge-ghost'

    content_tag :span, role.titleize, class: "badge #{badge_class} badge-sm"
  end

  # Check if current page matches any of the given paths
  def active_nav_item?(*paths)
    paths.any? { |path| current_page?(path) }
  end

  # Format bytes to human-readable size
  def format_bytes(bytes)
    return '0 B' if bytes.nil? || bytes.zero?

    units = %w[B KB MB GB TB]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = [exp, units.length - 1].min

    "#{(bytes / (1024.0**exp)).round(2)} #{units[exp]}"
  end

  # Calculate percentage for progress bars
  def calculate_percentage(used, total)
    return 0 if total.nil? || total.zero?

    ((used.to_f / total.to_f) * 100).round(1)
  end

  # Render progress bar with color coding
  def progress_bar(percentage)
    color_class = if percentage >= 90
                    'progress-error'
                  elsif percentage >= 70
                    'progress-warning'
                  else
                    'progress-success'
                  end

    content_tag :progress, '',
                class: "progress #{color_class} w-full",
                value: percentage,
                max: 100
  end
end
