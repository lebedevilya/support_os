require "net/http"
require "json"
require "securerandom"
require "uri"

HOST        = ENV.fetch("REGRESSION_API_HOST", "https://supportos.ilyalebe.dev")
TOKEN       = Rails.application.credentials.dig(:regression_api, :token)
COMPANY     = ENV.fetch("REGRESSION_API_COMPANY", "aipassportphoto")
CONCURRENCY = ENV.fetch("REGRESSION_CONCURRENCY", "10").to_i

OPENERS = [
  "Hi",
  "Hello, can you help?",
  "Hey there",
  "Good afternoon",
  "I need some help"
].freeze

CASES = [
  # initial 40 dialogues (v1)
  "How much is the price per photo?",
  "What is included in the $4.99 option?",
  "What is included in the $7.99 option?",
  "How long does the process take?",
  "Do you offer a money-back guarantee?",
  "What happens if my photo gets rejected?",
  "What countries do you spport?",
  "Can you make a Canada passport photo?",
  "Can you make a UK visa photo?",
  "Do I need a professional camera?",
  "Do I need special lighting?",
  "Can I print the photo at home?",
  "Do I get a digital file or a PDF?",
  "How many photos are included in the print PDF?",
  "Will official agencies accept the photo?",
  "Do you delete uploaded photos?",
  "How long do you keep my photo?",
  "How can I contact support?",
  "Is payment secure?",
  "Can I upload a selfie from my phone?",
  "Do you support US passport photos?",
  "Do you support Germany passport photos?",
  "Can I use a normal selfie?",
  "Do I need to travel to a photo studio?",
  "Will I get a refund if an embassy rejects my photo?",
  "Is the PDF print-ready?",
  "Does the print version include cutting guides?",
  "Do you support India passport photos?",
  "Can I use my computer webcam?",
  "Do you have unlimited retakes?",
  "Can I make photo for Russian passport?",
  "Can you help me bake cookies?",
  "How much is the price for a fishing rod?",
  "Do you sell bicycle tires?",
  "Write me a poem about bananas.",
  "What is the weather in Tokyo today?",
  "Can you renew my passport for me?",
  "Do you guarantee embassy acceptance in every case?",
  "Can I use the service without paying?",
  "Can you email my photo to the embassy directly?",

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
  "Can I use the same photo for a UK passport and a UK driving licence?",

  # v2: additional 40 cases
  # Photo appearance requirements
  "Can I wear a hat in my passport photo?",
  "Does the photo need to be in color?",
  "Can I have my eyes closed in the photo?",
  "Can I use a black and white photo?",
  "My photo has shadows on the background, is that acceptable?",
  "Do I need to remove earrings for my passport photo?",
  "Can I have a beard in my passport photo?",
  "Can I wear makeup in my passport photo?",

  # More country coverage
  "Do you support Swiss passport photos?",
  "Can I make a photo for an Italian passport?",
  "What about a Spanish visa photo?",
  "Do you support Korean passport photos?",
  "Can you make a photo for a Mexican passport?",
  "Do you support South African passport photos?",
  "Can I make a photo for a New Zealand passport?",
  "Do you support UAE visa photos?",

  # Pricing and payment edge cases
  "Is there a free trial?",
  "Do you offer discounts for bulk orders?",
  "Can I pay with PayPal?",
  "Do you accept cryptocurrency?",
  "Can I get an invoice for my order?",
  "What currencies do you accept?",

  # Technical / product detail
  "What resolution is the final photo?",
  "Can I download the photo multiple times?",
  "Can I share my download link with someone else?",
  "What happens if the AI cannot process my photo?",
  "How do I download my photo on an iPhone?",

  # Delivery and account recovery
  "My email confirmation never arrived",
  "I accidentally deleted my download email, can you resend it?",
  "Can you resend my photo to a different email address?",
  "I ordered the wrong package, can I switch?",

  # Compliance and acceptance stress
  "Do you guarantee the photo will be accepted by TSA?",
  "Is your service approved by the US State Department?",
  "What if I changed my appearance since taking the photo?",
  "Can I take a photo wearing a religious head covering?",

  # Completely out-of-scope
  "What is the current passport application fee for the US?",
  "How do I renew my passport online?",
  "Where is the nearest passport office to me?",
  "Can you translate my passport application form?"
].freeze

def request(method, path, body = nil)
  uri = URI.join(HOST, path)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  request_class = case method
  when :get then Net::HTTP::Get
  when :post then Net::HTTP::Post
  else raise "Unsupported method: #{method}"
  end

  req = request_class.new(uri)
  req["Authorization"] = "Bearer #{TOKEN}"
  req["Content-Type"] = "application/json"
  req.body = JSON.dump(body) if body

  response = http.request(req)
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
    assistant_messages = payload.fetch("messages").select { |m| m["role"] == "assistant" }
    return [payload, assistant_messages.last] if assistant_messages.size > previous_assistant_count

    raise "Timed out waiting for assistant on ticket #{ticket_id}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    sleep 1
  end
end

def run_case(question, index)
  opener = OPENERS[index % OPENERS.length]
  email  = "qa+#{Time.now.to_i}-#{index}-#{SecureRandom.hex(4)}@example.com"
  ticket_id = nil
  opener_reply = nil

  created = request(:post, "/widget/test_api/tickets", company_slug: COMPANY, email: email, content: opener)
  ticket_id = ticket_payload(created).fetch("id")
  _opener_payload, opener_reply = wait_for_assistant(ticket_id, 0)

  request(:post, "/widget/test_api/tickets/#{ticket_id}/messages", content: question)
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

unless TOKEN.present?
  abort "Missing regression_api.token in Rails credentials"
end

queue   = Queue.new
CASES.each_with_index { |q, i| queue << [q, i] }

mutex   = Mutex.new
results = []
$stderr.print "Running #{CASES.size} cases with #{CONCURRENCY} threads"

workers = CONCURRENCY.times.map do
  Thread.new do
    until queue.empty?
      item = begin; queue.pop(true); rescue ThreadError; nil; end
      next unless item

      question, index = item
      result = run_case(question, index)
      mutex.synchronize do
        results << result
        $stderr.print(result[:error] ? "E" : ".")
      end
    end
  end
end

workers.each(&:join)
$stderr.puts "\nDone."

puts JSON.pretty_generate(results.sort_by { |r| CASES.index(r[:question]).to_i })
