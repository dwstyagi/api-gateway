# frozen_string_literal: true

# Base controller for all admin namespace controllers
# Ensures admin layout is used and admin authentication is enforced
class AdminController < ApplicationController
  layout 'admin'
  before_action :require_admin
end
