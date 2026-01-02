# frozen_string_literal: true

# Consumer Settings Controller
# Manage user account settings, profile, and security preferences
class Consumer::SettingsController < Consumer::ConsumerController
  def index
    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(user_params)
      redirect_to consumer_settings_path, notice: 'Profile updated successfully'
    else
      render :index, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
