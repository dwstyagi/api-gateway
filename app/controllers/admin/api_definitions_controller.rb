# frozen_string_literal: true

# Admin API Definitions Management Controller
#
# Endpoints for managing API definitions (backend routes):
# - List all API definitions
# - Create new API definitions
# - Update existing API definitions
# - Enable/disable APIs
# - Delete API definitions
#
# All endpoints require admin authentication
class Admin::ApiDefinitionsController < AdminController
  before_action :set_api_definition, only: [:show, :edit, :update, :destroy, :toggle]

  # GET /admin/api_definitions
  # List all API definitions
  def index
    api_defs = ApiDefinition.all

    # Filter by enabled status
    api_defs = api_defs.where(enabled: params[:enabled] == 'true') if params[:enabled].present?

    # Search by name or route
    if params[:search].present?
      api_defs = api_defs.where('name ILIKE ? OR route_pattern ILIKE ? OR backend_url ILIKE ?',
                                  "%#{params[:search]}%", "%#{params[:search]}%", "%#{params[:search]}%")
    end

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    per_page = [per_page, 100].min

    total = api_defs.count
    offset = (page - 1) * per_page

    api_defs = api_defs.order(created_at: :desc).limit(per_page).offset(offset)

    respond_to do |format|
      format.html do
        @api_definitions = api_defs
        render :index
      end

      format.json do
        render json: {
          success: true,
          data: api_defs.map { |api_def| serialize_api_definition(api_def) },
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

  # GET /admin/api_definitions/:id
  # Get detailed API definition information
  def show
    # Get associated rate limit policies
    policies = @api_definition.rate_limit_policies.map do |policy|
      {
        id: policy.id,
        tier: policy.tier,
        strategy: policy.strategy,
        capacity: policy.capacity,
        refill_rate: policy.refill_rate,
        window_size: policy.window_size
      }
    end

    render json: {
      success: true,
      data: {
        api_definition: serialize_api_definition(@api_definition),
        rate_limit_policies: policies,
        policies_count: policies.length
      }
    }
  end

  # GET /admin/api_definitions/new
  # Render form for creating a new API definition
  def new
    @api_definition = ApiDefinition.new
  end

  # POST /admin/api_definitions
  # Create a new API definition
  def create
    api_def = ApiDefinition.new(api_definition_params)

    if api_def.save
      log_admin_action('api_definition_created', api_def)

      respond_to do |format|
        format.html do
          redirect_to admin_api_definitions_path, notice: "API definition '#{api_def.name}' created successfully"
        end
        format.json do
          render json: {
            success: true,
            message: 'API definition created successfully',
            data: serialize_api_definition(api_def)
          }, status: :created
        end
      end
    else
      respond_to do |format|
        format.html do
          @api_definition = api_def
          flash.now[:alert] = "Failed to create API definition: #{api_def.errors.full_messages.join(', ')}"
          render :new, status: :unprocessable_entity
        end
        format.json do
          render json: {
            success: false,
            error: {
              code: 'VALIDATION_ERROR',
              message: 'Failed to create API definition',
              details: api_def.errors.full_messages
            }
          }, status: :unprocessable_entity
        end
      end
    end
  end

  # GET /admin/api_definitions/:id/edit
  # Render form for editing an API definition
  def edit
    # @api_definition is set by before_action
  end

  # PATCH/PUT /admin/api_definitions/:id
  # Update an API definition
  def update
    if @api_definition.update(api_definition_params)
      log_admin_action('api_definition_updated', @api_definition)

      respond_to do |format|
        format.html do
          redirect_to admin_api_definitions_path, notice: "API definition '#{@api_definition.name}' updated successfully"
        end
        format.json do
          render json: {
            success: true,
            message: 'API definition updated successfully',
            data: serialize_api_definition(@api_definition)
          }
        end
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = "Failed to update API definition: #{@api_definition.errors.full_messages.join(', ')}"
          render :edit, status: :unprocessable_entity
        end
        format.json do
          render json: {
            success: false,
            error: {
              code: 'VALIDATION_ERROR',
              message: 'Failed to update API definition',
              details: @api_definition.errors.full_messages
            }
          }, status: :unprocessable_entity
        end
      end
    end
  end

  # DELETE /admin/api_definitions/:id
  # Delete an API definition
  def destroy
    name = @api_definition.name

    # Check if there are associated rate limit policies
    if @api_definition.rate_limit_policies.exists?
      return render json: {
        success: false,
        error: {
          code: 'HAS_DEPENDENCIES',
          message: 'Cannot delete API definition with associated rate limit policies. Delete policies first.',
          details: {
            policies_count: @api_definition.rate_limit_policies.count
          }
        }
      }, status: :unprocessable_entity
    end

    @api_definition.destroy

    log_admin_action('api_definition_deleted', { name: name })

    render json: {
      success: true,
      message: 'API definition deleted successfully'
    }
  end

  # POST /admin/api_definitions/:id/toggle
  # Toggle enabled/disabled status
  def toggle
    @api_definition.update!(enabled: !@api_definition.enabled)

    log_admin_action('api_definition_toggled', {
      id: @api_definition.id,
      name: @api_definition.name,
      enabled: @api_definition.enabled
    })

    # Broadcast to admin WebSocket channel
    ActionCable.server.broadcast('admin:metrics', {
      type: @api_definition.enabled ? 'api_enabled' : 'api_disabled',
      data: {
        api_name: @api_definition.name,
        api_id: @api_definition.id,
        route_pattern: @api_definition.route_pattern,
        enabled: @api_definition.enabled,
        timestamp: Time.current.iso8601
      }
    })

    render json: {
      success: true,
      message: "API definition #{@api_definition.enabled ? 'enabled' : 'disabled'} successfully",
      data: serialize_api_definition(@api_definition)
    }
  end

  # GET /admin/api_definitions/stats
  # Get API definition statistics
  def stats
    total = ApiDefinition.count
    enabled = ApiDefinition.where(enabled: true).count
    disabled = ApiDefinition.where(enabled: false).count

    # Count by HTTP methods (rough approximation)
    with_get = ApiDefinition.where("'GET' = ANY(allowed_methods)").count
    with_post = ApiDefinition.where("'POST' = ANY(allowed_methods)").count
    with_put = ApiDefinition.where("'PUT' = ANY(allowed_methods)").count
    with_delete = ApiDefinition.where("'DELETE' = ANY(allowed_methods)").count

    render json: {
      success: true,
      data: {
        total: total,
        enabled: enabled,
        disabled: disabled,
        by_method: {
          get: with_get,
          post: with_post,
          put: with_put,
          delete: with_delete
        },
        total_policies: RateLimitPolicy.count
      }
    }
  end

  # POST /admin/api_definitions/:id/test
  # Test backend connectivity
  def test
    @api_definition = ApiDefinition.find(params[:id])

    begin
      # Make a simple HEAD request to test connectivity
      response = HTTParty.head(@api_definition.backend_url, timeout: 5)

      render json: {
        success: true,
        message: 'Backend is reachable',
        data: {
          status_code: response.code,
          response_time_ms: response.time * 1000,
          backend_url: @api_definition.backend_url
        }
      }
    rescue HTTParty::Error, Net::OpenTimeout, SocketError => e
      render json: {
        success: false,
        error: {
          code: 'BACKEND_UNREACHABLE',
          message: 'Failed to connect to backend',
          details: e.message
        }
      }, status: :service_unavailable
    end
  end

  private

  def set_api_definition
    @api_definition = ApiDefinition.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: 'API definition not found'
      }
    }, status: :not_found
  end

  def api_definition_params
    params.require(:api_definition).permit(
      :name,
      :route_pattern,
      :backend_url,
      :enabled,
      allowed_methods: []
    )
  end

  def serialize_api_definition(api_def)
    {
      id: api_def.id,
      name: api_def.name,
      route_pattern: api_def.route_pattern,
      backend_url: api_def.backend_url,
      allowed_methods: api_def.allowed_methods,
      enabled: api_def.enabled,
      created_at: api_def.created_at,
      updated_at: api_def.updated_at
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
