require "net/http"
require "json"
require "securerandom"
require "uri"

HOST = ENV.fetch("REGRESSION_API_HOST", "http://147.135.78.29")
TOKEN = Rails.application.credentials.dig(:regression_api, :token)
COMPANY = ENV.fetch("REGRESSION_API_COMPANY", "aipassportphoto")
OPENERS = [
  "Hi",
  "Hello, can you help?",
  "Hey there",
  "Good afternoon",
  "I need some help"
].freeze

# CASES V1 — original 40 cases, all passing as of sweep on 2026-04-23
# CASES = [
#   "How much is the price per photo?",
#   "What is included in the $4.99 option?",
#   "What is included in the $7.99 option?",
#   "How long does the process take?",
#   "Do you offer a money-back guarantee?",
#   "What happens if my photo gets rejected?",
#   "What countries do you support?",
#   "Can you make a Canada passport photo?",
#   "Can you make a UK visa photo?",
#   "Do I need a professional camera?",
#   "Do I need special lighting?",
#   "Can I print the photo at home?",
#   "Do I get a digital file or a PDF?",
#   "How many photos are included in the print PDF?",
#   "Will official agencies accept the photo?",
#   "Do you delete uploaded photos?",
#   "How long do you keep my photo?",
#   "How can I contact support?",
#   "Is payment secure?",
#   "Can I upload a selfie from my phone?",
#   "Do you support US passport photos?",
#   "Do you support Germany passport photos?",
#   "Can I use a normal selfie?",
#   "Do I need to travel to a photo studio?",
#   "Will I get a refund if an embassy rejects my photo?",
#   "Is the PDF print-ready?",
#   "Does the print version include cutting guides?",
#   "Do you support India passport photos?",
#   "Can I use my computer webcam?",
#   "Do you have unlimited retakes?",
#   "Can I make photo for Russian passport?",
#   "Can you help me bake cookies?",
#   "How much is the price for a fishing rod?",
#   "Do you sell bicycle tires?",
#   "Write me a poem about bananas.",
#   "What is the weather in Tokyo today?",
#   "Can you renew my passport for me?",
#   "Do you guarantee embassy acceptance in every case?",
#   "Can I use the service without paying?",
#   "Can you email my photo to the embassy directly?"
# ].freeze

CASES = [
  # Service-cannot-perform variants
  "Can you submit my visa application for me?",
  "Can you book a passport photo appointment at my local post office?",
  "Can you mail me a physical printed photo to my home address?",
  "Can you check if my existing passport photo already meets requirements?",
  "Can you check whether my current passport is still valid?",
  "Can you fill out my passport application form?",

  # Unsupported / unknown countries — should all get standard format answer
  "Do you support Australian passport photos?",
  "Can I make a photo for a French passport?",
  "Do you support Japanese visa photos?",
  "Can I make a photo for a Chinese passport?",
  "Do you support Brazilian passport photos?",
  "What about a Nigerian passport photo?",

  # Grounding stress — details likely absent from knowledge chunks
  "What is your refund processing time?",
  "How do I request a refund?",
  "What is your customer support phone number?",
  "Do you have a mobile app?",
  "What are your business hours?",
  "Do you have a referral or loyalty program?",

  # Photo requirement edge cases
  "Can I wear glasses in my passport photo?",
  "Am I allowed to smile in my passport photo?",
  "Can I wear a hijab in my passport photo?",
  "What background color does the photo need to have?",
  "Can I use a photo I took two years ago?",
  "What file format will I receive the finished photo in?",

  # Active delivery and account issues — exercises specialist path
  "I paid but never received my photo download link",
  "My download link is not working",
  "I need a refund, the embassy rejected my photo",
  "I entered the wrong email address when I placed my order",
  "I was charged twice for the same order",
  "Can I use the same photo I bought here for both my passport and my visa?",

  # Human handoff
  "I want to speak with a real person",
  "Can I talk to a human agent?",
  "I need to escalate this to a manager",
  "Your bot gave me completely wrong information and I am very frustrated",

  # Product scope edge cases
  "Is this photo suitable for a driving licence?",
  "Do you make ID card photos?",
  "Can you make a photo for a green card application?",
  "Can you make a passport photo for my baby?",
  "Do you support NEXUS card or Global Entry photos?",
  "Can I use the same photo for a UK passport and a UK driving licence?"
].freeze

def request(method, path, body = nil)
  uri = URI.join(HOST, path)
  http = Net::HTTP.new(uri.host, uri.port)
  request_class = case method
  when :get then Net::HTTP::Get
  when :post then Net::HTTP::Post
  else raise "Unsupported method: #{method}"
  end

  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{TOKEN}"
  request["Content-Type"] = "application/json"
  request.body = JSON.dump(body) if body

  response = http.request(request)
  raise "#{method.upcase} #{path} failed: #{response.code} #{response.body}" unless response.code.to_i.between?(200, 299)

  JSON.parse(response.body)
end

def ticket_payload(payload)
  payload.fetch("ticket", payload)
end

def wait_for_assistant(ticket_id, previous_assistant_count, timeout: 90)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

  loop do
    payload = ticket_payload(request(:get, "/widget/test_api/tickets/#{ticket_id}"))
    assistant_messages = payload.fetch("messages").select { |message| message["role"] == "assistant" }
    return [payload, assistant_messages.last] if assistant_messages.size > previous_assistant_count

    raise "Timed out waiting for assistant on ticket #{ticket_id}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    sleep 2
  end
end

unless TOKEN.present?
  abort "Missing regression_api.token in Rails credentials"
end

results = CASES.each_with_index.map do |question, index|
  opener = OPENERS[index % OPENERS.length]
  email = "qa+#{Time.now.to_i}-#{index}-#{SecureRandom.hex(4)}@example.com"

  created = request(
    :post,
    "/widget/test_api/tickets",
    company_slug: COMPANY,
    email: email,
    content: opener
  )

  ticket_id = ticket_payload(created).fetch("id")
  opener_payload, opener_reply = wait_for_assistant(ticket_id, 0)

  request(
    :post,
    "/widget/test_api/tickets/#{ticket_id}/messages",
    content: question
  )

  answer_payload, answer_reply = wait_for_assistant(ticket_id, 1)
  request(:post, "/widget/test_api/tickets/#{ticket_id}/close")

  {
    ticket_id: ticket_id,
    opener: opener,
    opener_reply: opener_reply["content"],
    question: question,
    answer: answer_reply["content"],
    status: answer_payload["status"],
    processing: answer_payload["processing"]
  }
rescue => error
  {
    ticket_id: ticket_id,
    opener: opener,
    opener_reply: opener_reply&.dig("content"),
    question: question,
    error: error.message
  }
end

puts JSON.pretty_generate(results)
