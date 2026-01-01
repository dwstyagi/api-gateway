# frozen_string_literal: true

# Admin API Keys Management Controller
#
# Endpoints for managing user API keys:
# - List all API keys across all users
# - View API key details and usage
# - Revoke API keys
# - Force rotate API keys
#
# All endpoints require admin authentication
class Admin::ApiKeysController < AdminController
  before_action :set_api_key, only: [:show, :destroy, :revoke]

  # GET /admin/api_keys
  # List all API keys with filtering
  def index
    api_keys = ApiKey.includes(:user).all

    # Filter by user
    api_keys = api_keys.where(user_id: params[:user_id]) if params[:user_id].present?

    # Filter by status
    api_keys = api_keys.where(status: params[:status]) if params[:status].present?

    # Search by name or prefix
    if params[:search].present?
      api_keys = api_keys.where('name ILIKE ? OR prefix ILIKE ?', "%#{params[:search]}%", "%#{params[:search]}%")
    end

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    per_page = [per_page, 100].min

    total = api_keys.count
    offset = (page - 1) * per_page

    api_keys = api_keys.order(created_at: :desc).limit(per_page).offset(offset)

    render json: {
      success: true,
      data: api_keys.map { |key| serialize_api_key(key) },
      pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: (total.to_f / per_page).ceil
      }
    }
  end

  # GET /admin/api_keys/:id
  # Get detailed API key information
  def show
    # Get usage statistics from Redis
    usage_stats = get_usage_stats(@api_key)

    render json: {
      success: true,
      data: {
        api_key: serialize_api_key(@api_key),
        usage: usage_stats,
        user: {
          id: @api_key.user.id,
          email: @api_key.user.email,
          tier: @api_key.user.tier
        }
      }
    }
  end

  # DELETE /admin/api_keys/:id
  # Permanently delete an API key
  def destroy
    user_email = @api_key.user.email
    key_name = @api_key.name

    @api_key.destroy

    log_admin_action('api_key_deleted', {
      user_email: user_email,
      key_name: key_name
    })

    render json: {
      success: true,
      message: 'API key deleted successfully'
    }
  end

  # POST /admin/api_keys/:id/revoke
  # Revoke an API key (soft delete)
  def revoke
    @api_key.update!(status: 'revoked')

    # Clear from Redis cache
    $redis.del("api_key:#{@api_key.prefix}")

    log_admin_action('api_key_revoked', @api_key)

    render json: {
      success: true,
      message: 'API key revoked successfully',
      data: serialize_api_key(@api_key)
    }
  end

  # POST /admin/api_keys/:id/activate
  # Reactivate a revoked API key
  def activate
    @api_key = ApiKey.find(params[:id])
    @api_key.update!(status: 'active')

    log_admin_action('api_key_activated', @api_key)

    render json: {
      success: true,
      message: 'API key activated successfully',
      data: serialize_api_key(@api_key)
    }
  end

  # GET /admin/api_keys/stats
  # Get API key statistics
  def stats
    total_keys = ApiKey.count
    active_keys = ApiKey.where(status: 'active').count
    revoked_keys = ApiKey.where(status: 'revoked').count

    # Keys created in last 7 days
    recent_keys = ApiKey.where('created_at > ?', 7.days.ago).count

    # Keys by scope (count keys that have specific scopes)
    common_scopes = ['read', 'write', 'admin']
    scopes_usage = {}
    common_scopes.each do |scope|
      scopes_usage[scope] = ApiKey.where("? = ANY(scopes)", scope).count
    end

    render json: {
      success: true,
      data: {
        total_keys: total_keys,
        active_keys: active_keys,
        revoked_keys: revoked_keys,
        recent_keys: recent_keys,
        by_scope: scopes_usage,
        keys_per_user_avg: (total_keys.to_f / User.count).round(2)
      }
    }
  end

  # POST /admin/api_keys/bulk_revoke
  # Bulk revoke API keys (by user or criteria)
  def bulk_revoke
    count = 0

    if params[:user_id].present?
      keys = ApiKey.where(user_id: params[:user_id], status: 'active')
      count = keys.count
      keys.update_all(status: 'revoked')

      # Clear from Redis
      keys.each { |key| $redis.del("api_key:#{key.prefix}") }

      log_admin_action('api_keys_bulk_revoked', {
        user_id: params[:user_id],
        count: count
      })
    elsif params[:ids].present?
      ids = params[:ids]
      keys = ApiKey.where(id: ids, status: 'active')
      count = keys.count
      keys.update_all(status: 'revoked')

      # Clear from Redis
      keys.each { |key| $redis.del("api_key:#{key.prefix}") }

      log_admin_action('api_keys_bulk_revoked', {
        ids: ids,
        count: count
      })
    end

    render json: {
      success: true,
      message: "#{count} API key(s) revoked successfully"
    }
  end

  private

  def set_api_key
    @api_key = ApiKey.includes(:user).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: 'API key not found'
      }
    }, status: :not_found
  end

  def get_usage_stats(api_key)
    # Try to get from Redis (if tracking is implemented)
    {
      total_requests: 0, # Would come from Redis/logs
      last_used_at: api_key.last_used_at,
      requests_today: 0,
      requests_this_week: 0
    }
  end

  def serialize_api_key(key)
    {
      id: key.id,
      name: key.name,
      prefix: key.prefix,
      scopes: key.scopes,
      status: key.status,
      last_used_at: key.last_used_at,
      expires_at: key.expires_at,
      created_at: key.created_at,
      user: {
        id: key.user.id,
        email: key.user.email,
        tier: key.user.tier
      }
    }
  end

  def log_admin_action(action, details)
    AuditLog.create(
      event_type: "admin.#{action}",
      user_id: current_user&.id,
      actor_ip: request.ip,
      metadata: details.is_a?(Hash) ? details : { id: details.try(:id) }
    )
  end
end
