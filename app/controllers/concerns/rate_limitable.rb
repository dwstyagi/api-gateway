# frozen_string_literal: true

# RateLimitable Concern
#
# Handles concurrency limiter cleanup for controllers
# Ensures concurrency slots are released after request completes

module RateLimitable
  extend ActiveSupport::Concern

  included do
    # Release concurrency slot after action completes
    after_action :release_concurrency_slot
  end

  private

  # Release concurrency slot if one was acquired
  # This is critical for concurrency limiting - failure to release causes "leaks"
  def release_concurrency_slot
    limiter = request.env['rate_limiter']
    identifier = request.env['rate_limit_identifier']

    # Only release if we acquired a slot (concurrency strategy)
    return unless limiter.is_a?(RateLimiters::ConcurrencyRateLimiter)
    return unless identifier

    limiter.release(identifier)
  rescue StandardError => e
    # Log but don't fail the request
    Rails.logger.error("Failed to release concurrency slot: #{e.message}")
  end
end
