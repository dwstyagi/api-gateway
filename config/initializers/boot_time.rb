# frozen_string_literal: true

# Track application boot time for uptime calculations
Rails.application.config.booted_at = Time.current
