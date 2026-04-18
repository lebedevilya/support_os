require "json"
require "net/http"
require "uri"

module LLM
  class Client
    OPENAI_URL = "https://api.openai.com/v1/responses".freeze
    DEFAULT_MODEL = "gpt-4.1-mini".freeze

    def self.build_from_env
      api_key = credentials_api_key.to_s.strip
      return if api_key.empty?

      new(api_key: api_key)
    end

    def initialize(api_key:, model: DEFAULT_MODEL, endpoint: OPENAI_URL)
      @api_key = api_key
      @model = model
      @endpoint = endpoint
    end

    def complete_json(task:, prompt:, context:)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = request_body(task: task, prompt: prompt, context: context).to_json
        http.request(request)
      end

      raise "OpenAI request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      content = extract_text(body)
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

    def uri
      @uri ||= URI.parse(@endpoint)
    end

    def request_body(task:, prompt:, context:)
      {
        model: @model,
        input: [
          {
            role: "system",
            content: [
              {
                type: "input_text",
                text: "You are a support automation model. Return JSON only. No markdown."
              }
            ]
          },
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: <<~PROMPT
                  Task: #{task}

                  Instructions:
                  #{prompt}

                  Context:
                  #{JSON.pretty_generate(context)}
                PROMPT
              }
            ]
          }
        ]
      }
    end

    def extract_text(body)
      output = body.fetch("output", [])
      content_item = output.flat_map { |item| item.fetch("content", []) }.find { |item| item["type"] == "output_text" }
      return content_item["text"].to_s if content_item

      body["output_text"].to_s
    end

    def strip_code_fences(content)
      content.gsub(/\A```json\s*/i, "").gsub(/\A```\s*/i, "").gsub(/```\s*\z/, "").strip
    end
  end
end
