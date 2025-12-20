# frozen_string_literal: true

# Health Check Controller
#
# Public endpoint for monitoring and load balancers

class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    # Check if Redis and Database are accessible
    redis_status = check_redis
    database_status = check_database

    status_code = (redis_status && database_status) ? :ok : :service_unavailable

    render json: {
      status: status_code == :ok ? 'healthy' : 'unhealthy',
      timestamp: Time.current.iso8601,
      services: {
        redis: redis_status ? 'up' : 'down',
        database: database_status ? 'up' : 'down'
      }
    }, status: status_code
  end

  private

  def check_redis
    $redis.ping == 'PONG'
  rescue StandardError
    false
  end

  def check_database
    ActiveRecord::Base.connection.active?
  rescue StandardError
    false
  end
end
