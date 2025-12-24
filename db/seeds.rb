# frozen_string_literal: true

# Seed data for API Gateway
puts "🌱 Seeding database..."

# Clear existing data (development only)
if Rails.env.development?
  puts "Clearing existing data..."
  RateLimitPolicy.destroy_all
  ApiKey.destroy_all
  ApiDefinition.destroy_all
  IpRule.destroy_all
  AuditLog.destroy_all
  User.destroy_all
end

# Create users
puts "Creating users..."

admin = User.find_or_create_by!(email: 'admin@gateway.local') do |u|
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.role = 'admin'
  u.tier = 'enterprise'
end
puts "  ✓ Admin user: admin@gateway.local / password123"

free_user = User.find_or_create_by!(email: 'free@gateway.local') do |u|
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.role = 'user'
  u.tier = 'free'
end
puts "  ✓ Free user: free@gateway.local / password123"

pro_user = User.find_or_create_by!(email: 'pro@gateway.local') do |u|
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.role = 'user'
  u.tier = 'pro'
end
puts "  ✓ Pro user: pro@gateway.local / password123"

# Create API definitions
puts "\nCreating API definitions..."

# JSONPlaceholder - Free public API for testing
posts_api = ApiDefinition.find_or_create_by!(name: 'jsonplaceholder-posts') do |api|
  api.route_pattern = '/api/posts/*'
  api.backend_url = 'https://jsonplaceholder.typicode.com'
  api.allowed_methods = ['GET', 'POST', 'PUT', 'DELETE']
  api.enabled = true
end
puts "  ✓ JSONPlaceholder Posts API: /api/posts/* → https://jsonplaceholder.typicode.com"

# HTTPBin - HTTP testing service
httpbin_api = ApiDefinition.find_or_create_by!(name: 'httpbin') do |api|
  api.route_pattern = '/api/test/*'
  api.backend_url = 'https://httpbin.org'
  api.allowed_methods = ['GET', 'POST', 'PUT', 'DELETE']
  api.enabled = true
end
puts "  ✓ HTTPBin API: /api/test/* → https://httpbin.org"

# Create rate limit policies
puts "\nCreating rate limit policies..."

# Free tier - Token Bucket (10 requests capacity, refill 1 per 6 seconds = ~10/min)
RateLimitPolicy.find_or_create_by!(api_definition: posts_api, tier: 'free') do |policy|
  policy.strategy = 'token_bucket'
  policy.capacity = 10
  policy.refill_rate = 1  # 1 token per second = 60/min (but capacity limits bursts)
  policy.redis_failure_mode = 'open'
end
puts "  ✓ Free tier for Posts API: 10 capacity, 1 token/sec (token bucket)"

# Pro tier - Token Bucket (100 requests capacity, refill 10 per second = ~600/min)
RateLimitPolicy.find_or_create_by!(api_definition: posts_api, tier: 'pro') do |policy|
  policy.strategy = 'token_bucket'
  policy.capacity = 100
  policy.refill_rate = 10   # 10 tokens per second
  policy.redis_failure_mode = 'open'
end
puts "  ✓ Pro tier for Posts API: 100 capacity, 10 tokens/sec (token bucket)"

# Enterprise tier - Sliding Window (1000 requests/minute)
RateLimitPolicy.find_or_create_by!(api_definition: posts_api, tier: 'enterprise') do |policy|
  policy.strategy = 'sliding_window'
  policy.capacity = 1000
  policy.window_seconds = 60
  policy.redis_failure_mode = 'open'
end
puts "  ✓ Enterprise tier for Posts API: 1000 req/min (sliding window)"

# HTTPBin - Fixed Window for all tiers
RateLimitPolicy.find_or_create_by!(api_definition: httpbin_api, tier: nil) do |policy|
  policy.strategy = 'fixed_window'
  policy.capacity = 50
  policy.window_seconds = 60
  policy.redis_failure_mode = 'open'
end
puts "  ✓ Default tier for HTTPBin: 50 req/min (fixed window)"

# Create API keys
puts "\nCreating API keys..."

# Free user API key
free_api_key = ApiKey.generate_for_user(
  free_user,
  name: 'Free User Test Key',
  scopes: ['posts:read']
)
puts "  ✓ Free user API key: #{free_api_key}"
puts "    Scopes: posts:read"

# Pro user API key
pro_api_key = ApiKey.generate_for_user(
  pro_user,
  name: 'Pro User Test Key',
  scopes: ['posts:read', 'posts:write']
)
puts "  ✓ Pro user API key: #{pro_api_key}"
puts "    Scopes: posts:read, posts:write"

# Admin API key
admin_api_key = ApiKey.generate_for_user(
  admin,
  name: 'Admin Master Key',
  scopes: ['*:*']
)
puts "  ✓ Admin API key: #{admin_api_key}"
puts "    Scopes: *:* (full access)"

puts "\n✅ Seed data created successfully!"
puts "\n📝 Quick Start Guide:"
puts "  1. Login: POST /auth/login with email=pro@gateway.local, password=password123"
puts "  2. Or use API key: X-API-Key: #{pro_api_key}"
puts "  3. Test gateway: GET /api/posts/1 (proxies to JSONPlaceholder)"
puts "  4. Test HTTPBin: GET /api/test/get"
puts "\n🔍 Try these endpoints:"
puts "  GET  /api/posts/1        → Fetch post #1"
puts "  GET  /api/posts          → List all posts"
puts "  POST /api/posts          → Create new post"
puts "  GET  /api/test/get       → HTTPBin GET test"
puts "  GET  /api/test/headers   → See request headers"
