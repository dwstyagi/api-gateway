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
class Admin::RateLimitPoliciesController < AdminController
  before_action :set_policy, only: [:show, :edit, :update, :destroy]

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

    respond_to do |format|
      format.html do
        @policies = policies
        @api_definitions = ApiDefinition.all.order(:name)
        render :index
      end

      format.json do
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
    end
  end

  # GET /admin/rate_limit_policies/new
  # New policy form
  def new
    @policy = RateLimitPolicy.new
    @api_definitions = ApiDefinition.all.order(:name)
  end

  # GET /admin/rate_limit_policies/:id/edit
  # Edit policy form
  def edit
    @api_definitions = ApiDefinition.all.order(:name)
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

      # Broadcast to admin WebSocket channel
      ActionCable.server.broadcast('admin:metrics', {
        type: 'policy_created',
        data: {
          policy_id: policy.id,
          api_name: policy.api_definition&.name || 'All APIs',
          tier: policy.tier,
          strategy: policy.strategy,
          capacity: policy.capacity,
          timestamp: Time.current.iso8601
        }
      })

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

      # Broadcast to admin WebSocket channel
      ActionCable.server.broadcast('admin:metrics', {
        type: 'policy_updated',
        data: {
          policy_id: @policy.id,
          api_name: @policy.api_definition&.name || 'All APIs',
          tier: @policy.tier,
          strategy: @policy.strategy,
          capacity: @policy.capacity,
          timestamp: Time.current.iso8601
        }
      })

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

  # POST /admin/rate_limit_policies/preview
  # Preview effective policy and blast radius BEFORE saving
  def preview
    policy_data = params[:rate_limit_policy] || params

    strategy = policy_data[:strategy]
    capacity = policy_data[:capacity]&.to_i
    refill_rate = policy_data[:refill_rate]&.to_i
    window_seconds = policy_data[:window_seconds]&.to_i
    tier = policy_data[:tier]
    api_definition_id = policy_data[:api_definition_id]

    # Calculate effective policy description
    effective = calculate_effective_policy(
      strategy: strategy,
      capacity: capacity,
      refill_rate: refill_rate,
      window_seconds: window_seconds
    )

    # Calculate blast radius
    impact = calculate_policy_blast_radius(tier, api_definition_id)

    render json: {
      success: true,
      effective: effective,
      impact: impact
    }
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

  def calculate_effective_policy(strategy:, capacity:, refill_rate: nil, window_seconds: nil)
    case strategy
    when 'token_bucket'
      requests_per_min = refill_rate ? refill_rate * 60 : 0
      requests_per_hour = refill_rate ? refill_rate * 3600 : 0
      {
        description: "#{capacity} burst capacity, #{refill_rate}/sec sustained (~#{requests_per_min} req/min, ~#{requests_per_hour} req/hour)",
        allows_bursts: true,
        sustained_rate: "#{refill_rate}/sec"
      }
    when 'fixed_window'
      window_min = window_seconds ? window_seconds / 60 : 0
      {
        description: "#{capacity} requests per #{window_min} minute window (resets at boundary)",
        allows_bursts: true,
        sustained_rate: "#{capacity}/#{window_min}min"
      }
    when 'sliding_window'
      window_min = window_seconds ? window_seconds / 60 : 0
      {
        description: "#{capacity} requests per #{window_min} minute sliding window (smooth)",
        allows_bursts: false,
        sustained_rate: "#{capacity}/#{window_min}min"
      }
    when 'leaky_bucket'
      requests_per_min = refill_rate ? refill_rate * 60 : 0
      {
        description: "#{capacity} queue capacity, #{refill_rate}/sec constant processing rate (~#{requests_per_min} req/min)",
        allows_bursts: false,
        sustained_rate: "#{refill_rate}/sec"
      }
    when 'concurrency'
      {
        description: "#{capacity} maximum concurrent requests (not rate-based)",
        allows_bursts: false,
        sustained_rate: "N/A (concurrency limit)"
      }
    else
      {
        description: 'Unknown strategy',
        allows_bursts: false,
        sustained_rate: 'N/A'
      }
    end
  end

  def calculate_policy_blast_radius(tier, api_definition_id)
    # Count affected users by tier
    if tier.present? && tier != 'all'
      user_count = User.where(tier: tier).count
      key_count = ApiKey.active.joins(:user).where(users: { tier: tier }).count
    else
      user_count = User.count
      key_count = ApiKey.active.count
    end

    # If specific API definition, get request metrics
    if api_definition_id.present?
      api_def = ApiDefinition.find_by(id: api_definition_id)
      metric_key = "api:#{api_definition_id}:requests:hour"
      hourly_requests = MetricsService.get_counter(metric_key) rescue 0
    else
      hourly_requests = 0
    end

    {
      affected_users: user_count,
      active_keys: key_count,
      requests_per_hour: hourly_requests || 0,
      tier: tier || 'all',
      api_name: api_def&.name || 'All APIs'
    }
  end
end
