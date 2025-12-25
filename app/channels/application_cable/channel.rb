# frozen_string_literal: true

module ApplicationCable
  # Base Channel
  #
  # All channels inherit from this class
  class Channel < ActionCable::Channel::Base
    private

    # Helper to check if current user is admin
    def admin?
      current_user&.admin?
    end

    # Reject subscription if not admin
    def reject_unless_admin!
      reject unless admin?
    end
  end
end
