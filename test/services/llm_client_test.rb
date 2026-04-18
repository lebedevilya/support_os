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
      assert_equal LLM::Client::DEFAULT_PROVIDER, client.instance_variable_get(:@provider)
    end
  end

  test "build_from_env returns nil when open ai credentials key is absent" do
    with_stubbed_credentials(nil) do
      client = LLM::Client.build_from_env

      assert_nil client
    end
  end

  test "complete_json delegates through an injected chat factory and symbolises the response" do
    fake_chat = FakeChat.new('{ "category": "policy", "route": "specialist", "confidence": 0.91 }')

    client = LLM::Client.new(
      api_key: "credential-key",
      chat_factory: ->(model:, provider:, api_key:) {
        assert_equal "gpt-4.1-mini", model
        assert_equal :openai, provider
        assert_equal "credential-key", api_key
        fake_chat
      }
    )

    response = client.complete_json(
      task: "triage",
      prompt: "Classify the request.",
      context: { latest_message: "Do you support Canada?" }
    )

    assert_equal(
      { category: "policy", route: "specialist", confidence: 0.91 },
      response
    )
    assert_includes fake_chat.prompt, "Task: triage"
    assert_includes fake_chat.prompt, "Classify the request."
    assert_includes fake_chat.prompt, "Do you support Canada?"
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

  class FakeChat
    attr_reader :prompt

    def initialize(response_content)
      @response_content = response_content
    end

    def ask(prompt)
      @prompt = prompt
      OpenStruct.new(content: @response_content)
    end
  end
end
