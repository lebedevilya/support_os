require "test_helper"
require Rails.root.join("app/services/llm/client")
require "ostruct"

class LlmClientTest < ActiveSupport::TestCase
  test "build_from_env uses rails credentials when open ai key is present" do
    with_stubbed_credentials("credential-key") do
      client = LLM::Client.build_from_env

      refute_nil client
      assert_equal "credential-key", client.instance_variable_get(:@api_key)
      assert_equal LLM::Client::DEFAULT_MODEL, client.instance_variable_get(:@model)
      assert_equal LLM::Client::OPENAI_URL, client.instance_variable_get(:@endpoint)
    end
  end

  test "build_from_env returns nil when open ai credentials key is absent" do
    with_stubbed_credentials(nil) do
      client = LLM::Client.build_from_env

      assert_nil client
    end
  end

  private

  def stubbed_credentials(key)
    OpenStruct.new(open_ai: OpenStruct.new(api_key: key))
  end

  def with_stubbed_credentials(key)
    application = Rails.application
    original_method = application.method(:credentials)

    application.singleton_class.define_method(:credentials) do
      OpenStruct.new(open_ai: OpenStruct.new(api_key: key))
    end

    yield
  ensure
    application.singleton_class.define_method(:credentials) do
      original_method.call
    end
  end
end
