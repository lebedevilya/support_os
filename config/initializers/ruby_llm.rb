RubyLLM.configure do |config|
  config.use_new_acts_as = true
  api_key = Rails.application.credentials.dig(:open_ai, :api_key).to_s.strip
  config.openai_api_key = api_key unless api_key.empty?
end
