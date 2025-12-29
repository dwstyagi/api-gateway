Rails.application.routes.draw do
  # WebSocket endpoint for Action Cable
  mount ActionCable.server => '/cable'

  # Health check endpoints (public)
  get '/health', to: 'health#show'
  get '/health/detailed', to: 'health#detailed'

  # Web Authentication (session-based)
  get '/login', to: 'sessions#new', as: 'login'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy', as: 'logout'
  get '/logout', to: 'sessions#destroy' # Support GET for logout links

  get '/signup', to: 'registrations#new', as: 'signup'
  post '/signup', to: 'registrations#create'

  # Admin Dashboard (requires admin role)
  get '/dashboard', to: 'dashboard#index', as: 'dashboard'

  # User Dashboard (requires any authenticated user)
  get '/account', to: 'user_dashboard#index', as: 'account'

  # Consumer Portal (Developer/API Consumer UI)
  namespace :consumer, path: 'developer' do
    # Screen 1: Dashboard - Confidence check
    get '/', to: 'dashboard#index', as: 'dashboard'

    # Screen 2: API Keys - Self-service key management
    resources :api_keys do
      member do
        post :rotate
        post :revoke
      end
    end

    # Screen 3: Usage - Rate limits and usage stats
    get 'usage', to: 'usage#index', as: 'usage'

    # Screen 4: Errors - Actionable error logs
    get 'errors', to: 'errors#index', as: 'errors'

    # Upgrade flow (placeholder)
    get 'upgrade', to: 'dashboard#upgrade', as: 'upgrade'
  end

  # Set login as homepage
  root 'sessions#new'

  # API Authentication endpoints (JWT-based, public)
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

    # Metrics and Observability
    resources :metrics, only: [:index] do
      collection do
        get :requests
        get :errors
        get :performance
        get :throughput
        get :timeseries
        post :reset
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Gateway proxy routes (catch-all - must be last!)
  # All requests not matched above will be proxied to backend services
  # The GatewayController will match against API definitions and forward requests
  match '/api/*path', to: 'gateway#proxy', via: :all, constraints: ->(req) { req.path !~ /\A\/api\/me/ }
  match '/*path', to: 'gateway#proxy', via: :all, constraints: ->(req) {
    # Only proxy if path matches an API definition pattern
    # This prevents proxying static assets and other Rails routes
    !req.path.start_with?('/health', '/auth', '/admin', '/assets', '/up', '/rails', '/developer', '/login', '/logout', '/signup', '/dashboard', '/account', '/cable')
  }
end
