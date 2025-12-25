# frozen_string_literal: true

# Consumer Errors Controller
# Screen 4: Errors & Blocks - Actionable error logs with fix suggestions
class Consumer::ErrorsController < Consumer::ConsumerController
  def index
    @error_type = params[:filter] || 'all'
    @errors = get_user_errors(filter: @error_type, limit: 50)

    # Enhance each error with suggestion
    @errors = @errors.map do |error|
      status_code = error.metadata&.dig('status_code')
      suggestion = generate_error_suggestion(status_code, error.metadata || {})

      {
        error: error,
        status_code: status_code,
        suggestion: suggestion
      }
    end
  end
end
