# frozen_string_literal: true

# Admin Rate Limit Policies Management Controller
#
# Endpoints for managing rate limit policies:
# - List all policies
# - Create new policies
# - Update existing policies
# - Delete policies
# - Test policy configuration
#
# All endpoints require admin authentication
class Admin::RateLimitPoliciesController < ApplicationController
  before_action :require_admin
  before_action :set_policy, only: [:show, :update, :destroy]

  # GET /admin/rate_limit_policies
  # List all rate limit policies
  def index
    policies = RateLimitPolicy.includes(:api_definition).all

    # Filter by API definition
    policies = policies.where(api_definition_id: params[:api_definition_id]) if params[:api_definition_id].present?

    # Filter by tier
    policies = policies.where(tier: params[:tier]) if params[:tier].present?

    # Filter by strategy
    policies = policies.where(strategy: params[:strategy]) if params[:strategy].present?

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    per_page = [per_page, 100].min

    total = policies.count
    offset = (page - 1) * per_page

    policies = policies.order(created_at: :desc).limit(per_page).offset(offset)

    render json: {
      success: true,
      data: policies.map { |policy| serialize_policy(policy) },
      pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: (total.to_f / per_page).ceil
      }
    }
  end

  # GET /admin/rate_limit_policies/:id
  # Get detailed policy information
  def show
    render json: {
      success: true,
      data: serialize_policy(@policy, detailed: true)
    }
  end

  # POST /admin/rate_limit_policies
  # Create a new rate limit policy
  def create
    policy = RateLimitPolicy.new(policy_params)

    if policy.save
      log_admin_action('rate_limit_policy_created', policy)

      render json: {
        success: true,
        message: 'Rate limit policy created successfully',
        data: serialize_policy(policy)
      }, status: :created
    else
      render json: {
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Failed to create rate limit policy',
          details: policy.errors.full_messages
        }
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /admin/rate_limit_policies/:id
  # Update a rate limit policy
  def update
    if @policy.update(policy_params)
      log_admin_action('rate_limit_policy_updated', @policy)

      render json: {
        success: true,
        message: 'Rate limit policy updated successfully',
        data: serialize_policy(@policy)
      }
    else
      render json: {
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Failed to update rate limit policy',
          details: @policy.errors.full_messages
        }
      }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/rate_limit_policies/:id
  # Delete a rate limit policy
  def destroy
    api_def_name = @policy.api_definition&.name
    tier = @policy.tier

    @policy.destroy

    log_admin_action('rate_limit_policy_deleted', {
      api_definition: api_def_name,
      tier: tier
    })

    render json: {
      success: true,
      message: 'Rate limit policy deleted successfully'
    }
  end

  # GET /admin/rate_limit_policies/strategies
  # Get available rate limiting strategies with descriptions
  def strategies
    strategies_info = {
      token_bucket: {
        name: 'Token Bucket',
        description: 'Allows burst traffic. Tokens are added at a constant rate, consumed on requests.',
        parameters: ['capacity', 'refill_rate'],
        use_case: 'Good for APIs that need to allow bursts while maintaining average rate',
        example: 'capacity: 100 (max tokens), refill_rate: 10 (tokens/sec)'
      },
      fixed_window: {
        name: 'Fixed Window',
        description: 'Simple counter reset at fixed intervals.',
        parameters: ['capacity', 'window_seconds'],
        use_case: 'Simple to understand, good for basic rate limiting',
        example: 'capacity: 1000 (requests), window_seconds: 3600 (1 hour)'
      },
      sliding_window: {
        name: 'Sliding Window',
        description: 'Smooths out burst at window boundaries using weighted average.',
        parameters: ['capacity', 'window_seconds'],
        use_case: 'Prevents boundary spikes, more accurate than fixed window',
        example: 'capacity: 1000 (requests), window_seconds: 3600 (1 hour)'
      },
      leaky_bucket: {
        name: 'Leaky Bucket',
        description: 'Processes requests at constant rate, queue overflow is dropped.',
        parameters: ['capacity', 'leak_rate'],
        use_case: 'Smooth traffic flow to backend, good for protecting slow backends',
        example: 'capacity: 100 (queue size), leak_rate: 10 (requests/sec)'
      },
      concurrency: {
        name: 'Concurrency Limiter',
        description: 'Limits concurrent requests, not rate. Requires explicit release.',
        parameters: ['max_concurrent'],
        use_case: 'Protect backends from too many simultaneous connections',
        example: 'max_concurrent: 50 (simultaneous requests)'
      }
    }

    render json: {
      success: true,
      data: strategies_info
    }
  end

  # GET /admin/rate_limit_policies/stats
  # Get policy statistics
  def stats
    total = RateLimitPolicy.count
    by_strategy = RateLimitPolicy.group(:strategy).count
    by_tier = RateLimitPolicy.group(:tier).count

    render json: {
      success: true,
      data: {
        total: total,
        by_strategy: by_strategy,
        by_tier: by_tier,
        api_definitions_with_policies: ApiDefinition.joins(:rate_limit_policies).distinct.count,
        api_definitions_without_policies: ApiDefinition.left_joins(:rate_limit_policies)
                                                      .where(rate_limit_policies: { id: nil }).count
      }
    }
  end

  # POST /admin/rate_limit_policies/:id/test
  # Test a policy configuration (validate parameters)
  def test
    @policy = RateLimitPolicy.find(params[:id])

    # Validate strategy-specific parameters
    errors = []

    case @policy.strategy
    when 'token_bucket'
      errors << 'capacity must be positive' if @policy.capacity.nil? || @policy.capacity <= 0
      errors << 'refill_rate must be positive' if @policy.refill_rate.nil? || @policy.refill_rate <= 0
    when 'fixed_window', 'sliding_window'
      errors << 'capacity must be positive' if @policy.capacity.nil? || @policy.capacity <= 0
      errors << 'window_seconds must be positive' if @policy.window_seconds.nil? || @policy.window_seconds <= 0
    when 'leaky_bucket'
      errors << 'capacity must be positive' if @policy.capacity.nil? || @policy.capacity <= 0
      errors << 'refill_rate must be positive' if @policy.refill_rate.nil? || @policy.refill_rate <= 0
    end

    if errors.any?
      render json: {
        success: false,
        error: {
          code: 'INVALID_CONFIGURATION',
          message: 'Policy configuration is invalid',
          details: errors
        }
      }, status: :unprocessable_entity
    else
      render json: {
        success: true,
        message: 'Policy configuration is valid',
        data: serialize_policy(@policy, detailed: true)
      }
    end
  end

  private

  def set_policy
    @policy = RateLimitPolicy.includes(:api_definition).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: 'Rate limit policy not found'
      }
    }, status: :not_found
  end

  def policy_params
    params.require(:rate_limit_policy).permit(
      :api_definition_id,
      :tier,
      :strategy,
      :capacity,
      :refill_rate,
      :window_seconds,
      :redis_failure_mode
    )
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

  def serialize_policy(policy, detailed: false)
    data = {
      id: policy.id,
      api_definition_id: policy.api_definition_id,
      tier: policy.tier,
      strategy: policy.strategy,
      capacity: policy.capacity,
      refill_rate: policy.refill_rate,
      window_seconds: policy.window_seconds,
      redis_failure_mode: policy.redis_failure_mode,
      created_at: policy.created_at,
      updated_at: policy.updated_at
    }

    if detailed && policy.api_definition
      data[:api_definition] = {
        id: policy.api_definition.id,
        name: policy.api_definition.name,
        route_pattern: policy.api_definition.route_pattern
      }
    else
      data[:api_definition_name] = policy.api_definition&.name
    end

    data
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
