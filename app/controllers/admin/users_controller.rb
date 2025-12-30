# frozen_string_literal: true

# Admin Users Management Controller
#
# Endpoints for managing gateway users:
# - List all users with filtering
# - View user details and usage
# - Update user tiers and roles
# - Deactivate/reactivate users
# - Force token revocation
#
# All endpoints require admin authentication
class Admin::UsersController < ApplicationController
  before_action :require_admin
  before_action :set_user, only: [:show, :update, :destroy, :revoke_tokens]

  # GET /admin/users
  # List all users with filtering
  def index
    users = User.includes(:api_keys).all

    # Filter by role
    users = users.where(role: params[:role]) if params[:role].present?

    # Filter by tier
    users = users.where(tier: params[:tier]) if params[:tier].present?

    # Search by email
    users = users.where('email ILIKE ?', "%#{params[:search]}%") if params[:search].present?

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    per_page = [per_page, 100].min

    total = users.count
    offset = (page - 1) * per_page

    users = users.order(created_at: :desc).limit(per_page).offset(offset)

    respond_to do |format|
      format.html do
        @users = users
        @stats = {
          total: total,
          by_tier: User.group(:tier).count,
          by_role: User.group(:role).count
        }
        render :index
      end

      format.json do
        render json: {
          success: true,
          data: users.map { |user| serialize_user(user) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end
    end
  end

  # GET /admin/users/:id
  # Get detailed user information
  def show
    # Get user's API keys
    api_keys = @user.api_keys.map do |key|
      {
        id: key.id,
        name: key.name,
        prefix: key.prefix,
        scopes: key.scopes,
        status: key.status,
        last_used_at: key.last_used_at,
        created_at: key.created_at
      }
    end

    # Get recent audit logs
    recent_logs = AuditLog.where(user_id: @user.id)
                          .order(created_at: :desc)
                          .limit(10)

    render json: {
      success: true,
      data: {
        user: serialize_user(@user),
        api_keys: api_keys,
        api_keys_count: @user.api_keys.count,
        active_api_keys_count: @user.api_keys.where(status: 'active').count,
        recent_activity: recent_logs.map { |log| serialize_audit_log(log) }
      }
    }
  end

  # POST /admin/users
  # Create a new user (admin use case)
  def create
    user = User.new(user_create_params)

    if user.save
      log_admin_action('user_created', user)

      render json: {
        success: true,
        message: 'User created successfully',
        data: serialize_user(user)
      }, status: :created
    else
      render json: {
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Failed to create user',
          details: user.errors.full_messages
        }
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /admin/users/:id
  # Update user tier, role, or other attributes
  def update
    if @user.update(user_update_params)
      log_admin_action('user_updated', @user)

      render json: {
        success: true,
        message: 'User updated successfully',
        data: serialize_user(@user)
      }
    else
      render json: {
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Failed to update user',
          details: @user.errors.full_messages
        }
      }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/users/:id
  # Deactivate a user (soft delete)
  def destroy
    # Don't allow deleting yourself
    if @user.id == current_user.id
      return render json: {
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: 'Cannot delete your own account'
        }
      }, status: :forbidden
    end

    # Revoke all API keys
    @user.api_keys.update_all(status: 'revoked')

    # Increment token version to invalidate all JWTs
    @user.increment!(:token_version)

    # Mark user as inactive (or delete if you prefer hard delete)
    @user.update(active: false) if @user.respond_to?(:active)

    log_admin_action('user_deleted', @user)

    render json: {
      success: true,
      message: 'User deactivated successfully'
    }
  end

  # POST /admin/users/:id/revoke_tokens
  # Force revoke all user's JWT tokens
  def revoke_tokens
    @user.increment!(:token_version)

    log_admin_action('tokens_revoked', {
      user_id: @user.id,
      email: @user.email
    })

    respond_to do |format|
      format.html do
        redirect_to admin_users_path, notice: "All tokens revoked for #{@user.email}. User must re-authenticate."
      end
      format.json do
        render json: {
          success: true,
          message: 'All tokens revoked successfully. User must re-authenticate.'
        }
      end
    end
  end

  # POST /admin/users/:id/change_tier
  # Change user's subscription tier
  def change_tier
    @user = User.find(params[:id])
    new_tier = params[:new_tier] || params[:tier]
    reason = params[:reason]

    unless User::TIERS.include?(new_tier)
      respond_to do |format|
        format.html do
          redirect_to admin_users_path, alert: "Invalid tier. Must be one of: #{User::TIERS.join(', ')}"
        end
        format.json do
          render json: {
            success: false,
            error: {
              code: 'INVALID_TIER',
              message: "Invalid tier. Must be one of: #{User::TIERS.join(', ')}"
            }
          }, status: :unprocessable_entity
        end
      end
      return
    end

    old_tier = @user.tier
    @user.update!(tier: new_tier)

    log_admin_action('tier_changed', {
      user_id: @user.id,
      email: @user.email,
      old_tier: old_tier,
      new_tier: new_tier,
      reason: reason
    })

    # Broadcast to admin WebSocket channel
    ActionCable.server.broadcast('admin:metrics', {
      type: 'tier_changed',
      data: {
        user_id: @user.id,
        user_email: @user.email,
        old_tier: old_tier,
        new_tier: new_tier,
        reason: reason,
        timestamp: Time.current.iso8601
      }
    })

    respond_to do |format|
      format.html do
        redirect_to admin_users_path, notice: "User tier changed from #{old_tier} to #{new_tier}"
      end
      format.json do
        render json: {
          success: true,
          message: "User tier changed from #{old_tier} to #{new_tier}",
          data: serialize_user(@user)
        }
      end
    end
  end

  # GET /admin/users/stats
  # Get user statistics
  def stats
    total_users = User.count
    users_by_tier = User.group(:tier).count
    users_by_role = User.group(:role).count

    # Users created in last 7 days
    recent_signups = User.where('created_at > ?', 7.days.ago).count

    render json: {
      success: true,
      data: {
        total_users: total_users,
        by_tier: users_by_tier,
        by_role: users_by_role,
        recent_signups: recent_signups,
        total_api_keys: ApiKey.count,
        active_api_keys: ApiKey.where(status: 'active').count
      }
    }
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: 'User not found'
      }
    }, status: :not_found
  end

  def user_create_params
    params.require(:user).permit(:email, :password, :password_confirmation, :role, :tier)
  end

  def user_update_params
    params.require(:user).permit(:email, :role, :tier)
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

  def serialize_user(user)
    {
      id: user.id,
      email: user.email,
      role: user.role,
      tier: user.tier,
      token_version: user.token_version,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  def serialize_audit_log(log)
    {
      id: log.id,
      event_type: log.event_type,
      actor_ip: log.actor_ip,
      metadata: log.metadata,
      created_at: log.created_at
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
