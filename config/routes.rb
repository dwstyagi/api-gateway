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
    # Users Management
    resources :users do
      collection do
        get :stats
      end
      member do
        post :revoke_tokens
        post :change_tier
      end
    end

    # API Keys Management
    resources :api_keys, only: [:index, :show, :destroy] do
      collection do
        get :stats
        post :bulk_revoke
      end
      member do
        post :revoke
        post :activate
      end
    end

    # API Definitions Management
    resources :api_definitions do
      collection do
        get :stats
      end
      member do
        post :toggle
        post :test
      end
    end

    # Rate Limit Policies Management
    resources :rate_limit_policies do
      collection do
        get :strategies
        get :stats
      end
      member do
        post :test
      end
    end

    # Audit Logs (read-only)
    resources :audit_logs, only: [:index, :show] do
      collection do
        get :stats
        get :event_types
        get :export
        get :timeline
      end
    end

    # IP Rules Management
    get 'ip_rules/violations/:ip', to: 'ip_rules#violations', constraints: { ip: /[^\/]+/ }
    resources :ip_rules do
      collection do
        post :block, to: 'ip_rules#block_ip'
        post :unblock, to: 'ip_rules#unblock_ip'
        get :blocked, to: 'ip_rules#blocked_ips'
        post :clear_violations
      end
    end
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
