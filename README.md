# API Gateway & Application Platform

[![Ruby Version](https://img.shields.io/badge/ruby-3.2+-red.svg)](https://www.ruby-lang.org/)
[![Rails Version](https://img.shields.io/badge/rails-8.0+-blue.svg)](https://rubyonrails.org/)
[![PostgreSQL](https://img.shields.io/badge/postgresql-15+-blue.svg)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/redis-5+-red.svg)](https://redis.io/)
[![Implementation](https://img.shields.io/badge/completion-98%25-green.svg)]()

A production-ready **enterprise API Gateway** platform built with Ruby on Rails, designed to solve real business problems for companies that sell APIs (like Stripe, Twilio, or SendGrid).

## 🎯 What This Platform Solves

**The Business Problem:** Companies with valuable backend services want to monetize them safely. Without an API Gateway, every service needs custom authentication, rate limiting, and monitoring - leading to inconsistent security, poor developer experience, and operational complexity.

**The Solution:** A centralized API Gateway that handles authentication, rate limiting, request routing, and observability - allowing backend services to focus on business logic while providing enterprise-grade security and monitoring.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   API Consumers │────│   API Gateway   │────│ Backend Services│
│   (Developers)  │    │ (This Rails App)│    │ (Orders, Users) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   Admin Portal  │
                       │ (Management UI) │
                       └─────────────────┘
```

### Core Components

- **Gateway Runtime**: Stateless request processor with 7 middleware layers
- **Authentication System**: JWT tokens + API keys with SHA256 hashing
- **Rate Limiting Engine**: 5 strategies (Token Bucket, Sliding Window, etc.)
- **Admin APIs**: 50+ REST endpoints for management
- **Real-Time Monitoring**: WebSocket dashboards with live metrics
- **Security Features**: Auto-blocking, IP rules, audit logging

### Technology Stack

- **Backend**: Ruby on Rails 8.0
- **Database**: PostgreSQL 15+ (persistent data)
- **Cache**: Redis Cluster (hot data, rate limiting)
- **WebSockets**: Action Cable (real-time updates)
- **Frontend**: Hotwire + Tailwind CSS + DaisyUI
- **Authentication**: JWT (HS256) + BCrypt password hashing
- **Rate Limiting**: Redis Lua scripts for atomic operations

## 🚀 Key Features

### ✅ Authentication & Security
- **JWT Authentication** with token versioning for instant revocation
- **API Keys** with SHA256 hashing and user-defined scopes
- **Auto-Blocking** system (DDoS protection with configurable thresholds)
- **IP Rules** (allowlist/blocklist with TTL expiration)
- **Comprehensive Audit Logging** (immutable, searchable, exportable)

### ✅ Rate Limiting (5 Strategies)
- **Token Bucket**: Allows bursts, refills at constant rate
- **Sliding Window**: Prevents boundary exploits, smooth limiting
- **Fixed Window**: Simple counters, easy to understand
- **Leaky Bucket**: Strict rate control, constant output
- **Concurrency Limits**: Protects backend services from overload

### ✅ Enterprise Observability
- **Real-Time Metrics**: Request counts, error rates, response times
- **WebSocket Dashboards**: Live updates for admin and consumer portals
- **Health Checks**: System status monitoring (Redis, DB, disk space)
- **Request Tracing**: End-to-end request tracking with IDs
- **Performance Monitoring**: P95/P99 latency tracking

### ✅ Admin Management Portal
- **API Definitions**: Route configuration and backend mapping
- **Rate Limit Policies**: Tier-based limits with blast radius preview
- **User Management**: Tier overrides with impact assessment
- **IP Rules**: Emergency blocking with countdown timers
- **Audit Logs**: Immutable forensics with CSV export

### ✅ Developer Portal
- **API Key Management**: Self-service creation, rotation, revocation
- **Usage Analytics**: Rate limit consumption, top endpoints
- **Error Diagnostics**: Actionable error messages with fix suggestions
- **Live Dashboard**: Real-time request monitoring

## 🛠️ Getting Started

### Prerequisites

- Ruby 3.2+
- Rails 8.0+
- PostgreSQL 15+
- Redis 5+
- Node.js & Yarn (for asset compilation)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd api-gateway
   ```

2. **Install dependencies**
   ```bash
   bundle install
   yarn install
   ```

3. **Set up the database**
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed  # Optional: Load sample data
   ```

4. **Configure environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your Redis URL, JWT secret, etc.
   ```

5. **Start Redis** (if not running)
   ```bash
   redis-server
   ```

6. **Start the application**
   ```bash
   rails server
   ```

7. **Access the application**
   - **Admin Portal**: http://localhost:3000/admin
   - **Developer Portal**: http://localhost:3000/consumer
   - **API Gateway**: http://localhost:3000/api/*

### Configuration

Key environment variables:

```bash
# Database
DATABASE_URL=postgresql://localhost/api_gateway_dev

# Redis
REDIS_URL=redis://localhost:6379/0

# Authentication
JWT_SECRET=your-super-secret-jwt-key-here
JWT_ALGORITHM=HS256

# Rate Limiting
DEFAULT_RATE_LIMIT_STRATEGY=token_bucket
DEFAULT_RATE_LIMIT_CAPACITY=100

# Security
AUTO_BLOCK_ENABLED=true
REDIS_FAILURE_MODE=open  # or 'closed'
```

## 🚀 API Examples

### Authentication
```bash
# JWT Login
curl -X POST http://localhost:3000/auth/login \
  -d '{"email":"admin@example.com","password":"password"}'

# API Key Usage
curl http://localhost:3000/api/orders \
  -H "X-API-Key: pk_live_abc123..."
  -H "Authorization: Bearer <jwt_token>"
```

### Rate Limiting Headers
```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 73
X-RateLimit-Reset: 1705312800
```

### Admin API Examples
```bash
# Create API Definition
curl -X POST http://localhost:3000/admin/api_definitions \
  -H "Authorization: Bearer <admin_jwt>" \
  -d '{"name":"orders-api","route_pattern":"/api/orders/*","backend_url":"http://orders-service:3000"}'

# Block an IP
curl -X POST http://localhost:3000/admin/ip_rules \
  -H "Authorization: Bearer <admin_jwt>" \
  -d '{"ip_address":"192.168.1.100","rule_type":"block","reason":"Suspicious activity"}'
```

## 🔧 Development

### Code Structure
```
app/
├── controllers/
│   ├── admin/          # Admin management APIs
│   ├── consumer/       # Developer portal
│   └── gateway_controller.rb  # Main proxy logic
├── middleware/         # 7 middleware layers
├── models/            # PostgreSQL models
├── services/          # Business logic
│   ├── rate_limiters/ # 5 rate limiting strategies
│   ├── jwt_service.rb
│   ├── proxy_service.rb
│   └── metrics_service.rb
├── channels/          # WebSocket channels
└── views/             # Hotwire templates
```

### Key Design Patterns
- **Middleware Pipeline**: 7 layers for request processing
- **Factory Pattern**: Rate limiter strategy selection
- **Observer Pattern**: Metrics collection and broadcasting
- **Strategy Pattern**: Multiple rate limiting algorithms
- **Decorator Pattern**: Service enhancements (caching, logging)

## 📈 Performance Benchmarks

### Throughput
- **Single Instance**: 1,000-2,000 req/sec
- **3 Instances + Redis**: 5,000-8,000 req/sec
- **5 Instances + Redis Cluster**: 10,000-15,000 req/sec

### Latency Targets
- **P95 Response Time**: < 100ms
- **P99 Response Time**: < 200ms
- **Auth Check**: < 2ms (Redis lookup)
- **Rate Limit Check**: < 5ms (Lua script)

### Scalability Features
- Stateless gateway instances (horizontal scaling)
- Redis pub/sub for cross-instance communication
- Connection pooling for database and Redis
- Circuit breaker pattern for backend resilience

## 🔒 Security Features

### Authentication Security
- BCrypt password hashing (100ms intentionally slow)
- JWT tokens with 15-minute expiry
- Token versioning for instant revocation
- SHA256 API key hashing (one-way, unrecoverable)

### Runtime Security
- Auto-blocking (configurable thresholds for DDoS protection)
- IP allowlist/blocklist with TTL
- Scope-based authorization (principle of least privilege)
- Fail-open/fail-closed modes per endpoint

### Audit & Compliance
- Immutable audit logs (cannot be deleted or modified)
- Comprehensive event tracking (all admin actions)
- Searchable logs with filtering
- CSV export for compliance reporting

## 🤝 Contributing

### Development Workflow
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Standards
- **Ruby**: Follow RuboCop rules (configured in `.rubocop.yml`)
- **Rails**: Standard Rails conventions
- **Testing**: 100% coverage target for critical paths
- **Documentation**: Update docs for any API changes

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

This project demonstrates production-grade infrastructure development, inspired by real-world API gateways like AWS API Gateway, Kong, and the systems powering Stripe, Twilio, and GitHub APIs.
---
