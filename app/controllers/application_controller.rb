class ApplicationController < ActionController::Base
  include ExceptionHandler

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Make current_user available in views
  helper_method :current_user

  private

  def current_user
    # Check session first (for web UI)
    if session[:user_id]
      @current_user ||= User.find_by(id: session[:user_id])
    end

    # Fall back to middleware-set user (for API requests)
    @current_user ||= request.env['current_user']
  end

  def require_admin
    unless current_user&.admin?
      respond_to do |format|
        format.html { redirect_to login_path, alert: 'Admin access required' }
        format.json do
          render json: {
            success: false,
            error: { code: 'FORBIDDEN', message: 'Admin access required' }
          }, status: :forbidden
        end
      end
    end
  end

  def require_user
    unless current_user
      respond_to do |format|
        format.html { redirect_to login_path, alert: 'Please login to continue' }
        format.json do
          render json: {
            success: false,
            error: { code: 'UNAUTHORIZED', message: 'Authentication required' }
          }, status: :unauthorized
        end
      end
    end
  end
end
