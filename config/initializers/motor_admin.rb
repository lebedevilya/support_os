Motor::Admin.middleware.use(Rack::Auth::Basic) do |username, password|
  expected_username = Rails.application.credentials.dig(:motor_admin, :username)
  expected_password = Rails.application.credentials.dig(:motor_admin, :password)

  ActiveSupport::SecurityUtils.secure_compare(username.to_s, expected_username.to_s) &
    ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password.to_s)
end
