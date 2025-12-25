# frozen_string_literal: true

# Register custom middleware
# Require the middleware files explicitly since they run before autoloading

require_relative '../../app/middleware/logger_middleware'
require_relative '../../app/middleware/request_parser_middleware'
require_relative '../../app/middleware/ip_rules_middleware'
require_relative '../../app/middleware/authentication_middleware'
require_relative '../../app/middleware/rate_limiting_middleware'
require_relative '../../app/middleware/metrics_middleware'
require_relative '../../app/middleware/response_transformer_middleware'

# Gateway Middleware Pipeline (order is critical!)
#
# 1. LoggerMiddleware - Wraps everything, logs all requests/responses
# 2. RequestParserMiddleware - Extracts headers, generates request ID, extracts client IP
# 3. IpRulesMiddleware - Checks IP blocklist/allowlist (security first!)
# 4. AuthenticationMiddleware - Validates JWT/API Key, identifies user
# 5. RateLimitingMiddleware - Enforces rate limits based on user tier and API definition
# 6. MetricsMiddleware - Tracks performance metrics, errors, and usage statistics
# 7. ResponseTransformerMiddleware - Adds security headers, CORS, gateway headers
#
# Note: The actual proxying happens in GatewayController after all middleware

Rails.application.config.middleware.use LoggerMiddleware
Rails.application.config.middleware.use RequestParserMiddleware
Rails.application.config.middleware.use IpRulesMiddleware
Rails.application.config.middleware.use AuthenticationMiddleware
Rails.application.config.middleware.use RateLimitingMiddleware
Rails.application.config.middleware.use MetricsMiddleware
Rails.application.config.middleware.use ResponseTransformerMiddleware
