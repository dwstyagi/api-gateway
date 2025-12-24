Rails.application.routes.draw do
  # Health check endpoint (public)
  get '/health', to: 'health#show'

  # Authentication endpoints (public)
  namespace :auth do
    post 'signup', to: 'authentication#signup'
    post 'login', to: 'authentication#login'
    post 'refresh', to: 'authentication#refresh'
    post 'logout', to: 'authentication#logout'
  end

  # Protected test endpoint (requires authentication)
  namespace :api do
    get 'me', to: 'users#me'
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root path
  root "health#show"

  # Gateway proxy routes (catch-all - must be last!)
  # All requests not matched above will be proxied to backend services
  # The GatewayController will match against API definitions and forward requests
  match '/api/*path', to: 'gateway#proxy', via: :all, constraints: ->(req) { req.path !~ /\A\/api\/me/ }
  match '/*path', to: 'gateway#proxy', via: :all, constraints: ->(req) {
    # Only proxy if path matches an API definition pattern
    # This prevents proxying static assets and other Rails routes
    !req.path.start_with?('/health', '/auth', '/assets', '/up', '/rails')
  }
end
