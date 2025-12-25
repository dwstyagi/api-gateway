# Dashboard Controller
# Displays metrics and analytics for admin users
class DashboardController < ApplicationController
  before_action :require_admin

  def index
    # Get all stats from the admin API endpoints
    @stats = {
      users: user_stats,
      api_keys: api_key_stats,
      api_definitions: api_definition_stats,
      rate_limit_policies: policy_stats,
      audit_logs: audit_log_stats
    }

    @recent_activity = AuditLog.includes(:actor)
                                .order(created_at: :desc)
                                .limit(10)
  end

  private

  def user_stats
    {
      total: User.count,
      by_tier: User.group(:tier).count,
      by_role: User.group(:role).count,
      recent_signups: User.where('created_at > ?', 7.days.ago).count,
      signups_by_day: User.where('created_at > ?', 30.days.ago)
                          .group_by_day(:created_at).count
    }
  end

  def api_key_stats
    {
      total: ApiKey.count,
      active: ApiKey.where(status: 'active').count,
      revoked: ApiKey.where(status: 'revoked').count,
      by_status: ApiKey.group(:status).count,
      created_by_day: ApiKey.where('created_at > ?', 30.days.ago)
                            .group_by_day(:created_at).count
    }
  end

  def api_definition_stats
    {
      total: ApiDefinition.count,
      enabled: ApiDefinition.where(enabled: true).count,
      disabled: ApiDefinition.where(enabled: false).count
    }
  end

  def policy_stats
    {
      total: RateLimitPolicy.count,
      by_strategy: RateLimitPolicy.group(:strategy).count,
      by_tier: RateLimitPolicy.group(:tier).count
    }
  end

  def audit_log_stats
    {
      total: AuditLog.count,
      today: AuditLog.where('created_at > ?', 1.day.ago).count,
      this_week: AuditLog.where('created_at > ?', 7.days.ago).count,
      by_event_type: AuditLog.where('created_at > ?', 7.days.ago)
                              .group(:event_type).count
                              .sort_by { |k, v| -v }.first(10).to_h,
      events_by_day: AuditLog.where('created_at > ?', 30.days.ago)
                             .group_by_day(:created_at).count
    }
  end
end
