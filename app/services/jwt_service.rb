# frozen_string_literal: true

# JWT Service for API Gateway Authentication
#
# Handles:
# - Access token generation (short-lived, 15 minutes)
# - Refresh token generation (long-lived, 7 days)
# - Token verification with signature, expiry, and version checks
# - Token blacklisting for logout
# - Refresh token rotation
#
# Security features:
# - Token versioning for instant revocation
# - Blacklist support for individual token revocation
# - Short-lived access tokens + long-lived refresh tokens pattern
# - Refresh token rotation on use

class JwtService
  # Custom exceptions for better error handling
  class TokenExpiredError < StandardError; end
  class TokenInvalidError < StandardError; end
  class TokenRevokedError < StandardError; end
  class TokenVersionMismatchError < StandardError; end

  # Token configuration
  ACCESS_TOKEN_EXPIRY = ENV.fetch('ACCESS_TOKEN_EXPIRY', 900).to_i  # 15 minutes default
  REFRESH_TOKEN_EXPIRY = ENV.fetch('REFRESH_TOKEN_EXPIRY', 604800).to_i  # 7 days default
  SECRET_KEY = ENV.fetch('JWT_SECRET') { Rails.application.secret_key_base }
  ALGORITHM = ENV.fetch('JWT_ALGORITHM', 'HS256')

  class << self
    # Generate access and refresh tokens for a user
    #
    # @param user [User] The user to generate tokens for
    # @return [Hash] { access_token: String, refresh_token: String, expires_in: Integer }
    def generate_tokens(user)
      access_token = encode_access_token(user)
      refresh_token = encode_refresh_token(user)

      {
        access_token: access_token,
        refresh_token: refresh_token,
        token_type: 'Bearer',
        expires_in: ACCESS_TOKEN_EXPIRY
      }
    end

    # Encode an access token
    #
    # Access tokens are short-lived and contain user permissions
    # Verified on every API request
    #
    # @param user [User]
    # @return [String] JWT token
    def encode_access_token(user)
      now = Time.current.to_i

      payload = {
        # Standard JWT claims
        sub: user.id,                    # Subject (user ID)
        iat: now,                        # Issued at
        exp: now + ACCESS_TOKEN_EXPIRY,  # Expiration
        jti: generate_jti,               # JWT ID (unique identifier)

        # Custom claims
        type: 'access',
        role: user.role,
        tier: user.tier,
        token_version: user.token_version  # For revocation via version bump
      }

      JWT.encode(payload, SECRET_KEY, ALGORITHM)
    end

    # Encode a refresh token
    #
    # Refresh tokens are long-lived and used to get new access tokens
    # Stored in Redis for revocation tracking
    #
    # @param user [User]
    # @return [String] JWT token
    def encode_refresh_token(user)
      now = Time.current.to_i
      jti = generate_jti

      payload = {
        sub: user.id,
        iat: now,
        exp: now + REFRESH_TOKEN_EXPIRY,
        jti: jti,
        type: 'refresh',
        token_version: user.token_version
      }

      token = JWT.encode(payload, SECRET_KEY, ALGORITHM)

      # Store refresh token in Redis for tracking and revocation
      store_refresh_token(user.id, jti, REFRESH_TOKEN_EXPIRY)

      token
    end

    # Decode and verify a token
    #
    # Performs multiple security checks:
    # - Signature verification
    # - Expiry check
    # - Token version check (for revocation)
    # - Blacklist check
    #
    # @param token [String] JWT token
    # @param token_type [String] 'access' or 'refresh'
    # @return [Hash] Decoded payload
    # @raise [TokenExpiredError] if token is expired
    # @raise [TokenInvalidError] if signature is invalid
    # @raise [TokenRevokedError] if token is blacklisted
    # @raise [TokenVersionMismatchError] if token version doesn't match user's current version
    def decode(token, token_type: 'access')
      # Decode and verify signature
      decoded = JWT.decode(token, SECRET_KEY, true, { algorithm: ALGORITHM })
      payload = decoded[0]

      # Verify token type
      unless payload['type'] == token_type
        raise TokenInvalidError, "Expected #{token_type} token, got #{payload['type']}"
      end

      # Check if token is blacklisted
      if blacklisted?(payload['jti'])
        raise TokenRevokedError, 'Token has been revoked'
      end

      # Verify token version matches user's current version
      user = User.find_by(id: payload['sub'])
      unless user&.token_valid?(payload['token_version'])
        raise TokenVersionMismatchError, 'Token version is outdated'
      end

      payload

    rescue JWT::ExpiredSignature
      raise TokenExpiredError, 'Token has expired'
    rescue JWT::DecodeError => e
      raise TokenInvalidError, "Invalid token: #{e.message}"
    end

    # Refresh access token using refresh token
    #
    # Security: Implements refresh token rotation
    # - Old refresh token is invalidated
    # - New refresh token is issued
    # - Prevents refresh token reuse attacks
    #
    # @param refresh_token [String]
    # @return [Hash] { access_token: String, refresh_token: String, expires_in: Integer }
    # @raise [TokenExpiredError, TokenInvalidError, TokenRevokedError]
    def refresh_tokens(refresh_token)
      # Verify refresh token
      payload = decode(refresh_token, token_type: 'refresh')
      user = User.find(payload['sub'])

      # Invalidate old refresh token (rotation for security)
      blacklist_token(payload['jti'], REFRESH_TOKEN_EXPIRY)

      # Generate new tokens
      generate_tokens(user)
    end

    # Revoke a specific token by adding to blacklist
    #
    # @param token [String] JWT token to revoke
    # @param ttl [Integer] How long to keep in blacklist (seconds)
    def revoke_token(token)
      payload = JWT.decode(token, SECRET_KEY, true, { algorithm: ALGORITHM })[0]

      # Calculate remaining TTL (no need to blacklist expired tokens)
      remaining_ttl = payload['exp'] - Time.current.to_i
      return if remaining_ttl <= 0

      blacklist_token(payload['jti'], remaining_ttl)
    rescue JWT::DecodeError
      # Invalid token, no need to blacklist
      nil
    end

    # Check if token is blacklisted
    #
    # @param jti [String] JWT ID
    # @return [Boolean]
    def blacklisted?(jti)
      $redis.exists?("blacklist:#{jti}")
    end

    # Add token to blacklist
    #
    # @param jti [String] JWT ID
    # @param ttl [Integer] TTL in seconds
    def blacklist_token(jti, ttl)
      $redis.setex("blacklist:#{jti}", ttl, '1')
    end

    # Store refresh token in Redis for tracking
    #
    # @param user_id [String] User UUID
    # @param jti [String] Token ID
    # @param ttl [Integer] TTL in seconds
    def store_refresh_token(user_id, jti, ttl)
      $redis.setex("refresh_token:#{user_id}:#{jti}", ttl, Time.current.iso8601)
    end

    # Generate unique JWT ID (jti claim)
    #
    # @return [String] Random hex string
    def generate_jti
      SecureRandom.hex(16)
    end

    # Extract token from Authorization header
    #
    # Expected format: "Bearer <token>"
    #
    # @param header [String] Authorization header value
    # @return [String, nil] Token or nil if invalid format
    def extract_from_header(header)
      return nil if header.blank?

      parts = header.split(' ')
      return nil unless parts.length == 2 && parts[0] == 'Bearer'

      parts[1]
    end
  end
end
