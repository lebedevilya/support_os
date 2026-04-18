require "json"
require "ruby_llm"

module LLM
  class Client
    DEFAULT_MODEL = "gpt-4.1-mini".freeze
    DEFAULT_PROVIDER = :openai

    def self.build_from_env
      api_key = credentials_api_key.to_s.strip
      return if api_key.empty?

      new(api_key: api_key)
    end

    def initialize(api_key:, model: DEFAULT_MODEL, provider: DEFAULT_PROVIDER, endpoint: nil, chat_factory: nil)
      @api_key = api_key
      @model = model
      @provider = provider
      @endpoint = endpoint
      @chat_factory = chat_factory || method(:build_chat)
    end

    def complete_json(task:, prompt:, context:)
      response = @chat_factory.call(model: @model, provider: @provider, api_key: @api_key).ask(
        build_prompt(task: task, prompt: prompt, context: context)
      )
      content = response.content.to_s
      JSON.parse(strip_code_fences(content), symbolize_names: true)
    rescue JSON::ParserError => e
      raise "OpenAI returned invalid JSON for #{task}: #{e.message}"
    end

    private

    def self.credentials_api_key
      open_ai = Rails.application.credentials.respond_to?(:open_ai) ? Rails.application.credentials.open_ai : nil
      return open_ai.api_key if open_ai.respond_to?(:api_key)
      return open_ai[:api_key] if open_ai.respond_to?(:[])

      nil
    end

    def build_chat(model:, provider:, api_key:)
      RubyLLM.configure do |config|
        config.openai_api_key = api_key
      end

      RubyLLM.chat(model: model, provider: provider)
    end

    def build_prompt(task:, prompt:, context:)
      <<~PROMPT
        You are a support automation model. Return JSON only. No markdown.

        Task: #{task}

        Instructions:
        #{prompt}

        Context:
        #{JSON.pretty_generate(context)}
      PROMPT
    end

    def strip_code_fences(content)
      content.gsub(/\A```json\s*/i, "").gsub(/\A```\s*/i, "").gsub(/```\s*\z/, "").strip
    end
  end
end
