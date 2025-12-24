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

  # Admin endpoints (protected by authentication + admin check)
  namespace :admin do
    # IP Rules Management
    resources :ip_rules
    post 'ip_rules/block', to: 'ip_rules#block_ip'
    post 'ip_rules/unblock', to: 'ip_rules#unblock_ip'
    get 'ip_rules/blocked', to: 'ip_rules#blocked_ips'
    get 'ip_rules/violations/:ip', to: 'ip_rules#violations'
    post 'ip_rules/clear_violations', to: 'ip_rules#clear_violations'
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
    !req.path.start_with?('/health', '/auth', '/admin', '/assets', '/up', '/rails')
  }
end
