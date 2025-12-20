# frozen_string_literal: true

# Register custom middleware
# Require the middleware file explicitly since it runs before autoloading

require_relative '../../app/middleware/authentication_middleware'
require_relative '../../app/middleware/rate_limiting_middleware'

# Order matters:
# 1. AuthenticationMiddleware - Identifies user and sets current_user
# 2. RateLimitingMiddleware - Enforces rate limits based on user tier
Rails.application.config.middleware.use AuthenticationMiddleware
Rails.application.config.middleware.use RateLimitingMiddleware
