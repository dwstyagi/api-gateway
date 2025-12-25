# frozen_string_literal: true

# Consumer API Keys Controller
# Screen 2: Self-service API Key Management
class Consumer::ApiKeysController < Consumer::ConsumerController
  def index
    @api_keys = current_user.api_keys.order(created_at: :desc)
    @available_scopes = ApiKey::AVAILABLE_SCOPES
  end

  def new
    @api_key = ApiKey.new
    @available_scopes = ApiKey::AVAILABLE_SCOPES
    @environments = %w[test production]
  end

  def create
    result = ApiKey.generate_for_user(
      current_user,
      name: api_key_params[:name],
      scopes: api_key_params[:scopes] || [],
      environment: api_key_params[:environment] || 'test'
    )

    if result[:success]
      @api_key = result[:api_key]
      @raw_key = result[:raw_key]

      # Log the creation
      AuditLog.log_event(
        event_type: AuditLog::EventTypes::API_KEY_CREATED,
        actor_user: current_user,
        actor_ip: request.remote_ip,
        resource_type: 'ApiKey',
        resource_id: @api_key.id,
        metadata: {
          name: @api_key.name,
          environment: @api_key.prefix.include?('test') ? 'test' : 'production',
          scopes_count: @api_key.scopes.size
        }
      )

      # Show one-time display
      render :show_once
    else
      @api_key = ApiKey.new(api_key_params)
      @available_scopes = ApiKey::AVAILABLE_SCOPES
      @environments = %w[test production]
      flash.now[:alert] = result[:error] || 'Failed to create API key'
      render :new
    end
  end

  def rotate
    @api_key = current_user.api_keys.find(params[:id])

    # Deprecate old key
    @api_key.deprecate!

    # Create new key with same properties
    result = ApiKey.generate_for_user(
      current_user,
      name: "#{@api_key.name} (Rotated)",
      scopes: @api_key.scopes,
      environment: @api_key.prefix.include?('test') ? 'test' : 'production'
    )

    if result[:success]
      new_key = result[:api_key]
      @raw_key = result[:raw_key]

      # Log the rotation
      AuditLog.log_event(
        event_type: AuditLog::EventTypes::API_KEY_ROTATED,
        actor_user: current_user,
        actor_ip: request.remote_ip,
        resource_type: 'ApiKey',
        resource_id: new_key.id,
        change_details: {
          old_key_id: @api_key.id,
          new_key_id: new_key.id
        }
      )

      @api_key = new_key
      render :show_once
    else
      flash[:alert] = result[:error] || 'Failed to rotate API key'
      redirect_to consumer_api_keys_path
    end
  end

  def revoke
    @api_key = current_user.api_keys.find(params[:id])
    @api_key.revoke!

    # Log the revocation
    AuditLog.log_event(
      event_type: AuditLog::EventTypes::API_KEY_REVOKED,
      actor_user: current_user,
      actor_ip: request.remote_ip,
      resource_type: 'ApiKey',
      resource_id: @api_key.id
    )

    flash[:notice] = 'API key revoked successfully'
    redirect_to consumer_api_keys_path
  end

  def destroy
    @api_key = current_user.api_keys.find(params[:id])

    # Only allow deletion of revoked keys
    unless @api_key.status == 'revoked'
      flash[:alert] = 'Can only delete revoked API keys'
      redirect_to consumer_api_keys_path and return
    end

    @api_key.destroy

    flash[:notice] = 'API key deleted'
    redirect_to consumer_api_keys_path
  end

  private

  def api_key_params
    params.require(:api_key).permit(:name, :environment, scopes: [])
  end
end
