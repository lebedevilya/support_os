# SupportOS Technical Plan

## Summary

This document defines the technical plan for the current SupportOS demo.

The app should be a small Rails + Hotwire product that demonstrates a portfolio-wide support operating layer for two companies:

- `aipassportphoto`
- `nodes.garden`

The system should support:

- a live chat-style customer widget
- ticket-backed message threads
- an internal support inbox
- a ticket detail page
- a dedicated trace page

The runtime should use only 2 AI steps:

1. `TriageAgent`
2. `SpecialistAgent`

Human escalation is not an AI agent. It is a ticket state plus a handoff note.

The technical design should optimize for:

- credibility
- speed of implementation
- bounded AI behavior
- honest demo behavior

## Runtime Model

### Support flow

Every customer message should be attached to a ticket thread and processed through a bounded support pipeline.

The pipeline should work like this:

1. Create the user message on the ticket.
2. Run `TriageAgent`.
3. If triage says the issue can stay automated, run `SpecialistAgent`.
4. If either step fails or confidence is too low, escalate to human.
5. If the issue stays automated, create the assistant reply.
6. Update the ticket status and trace records.

### AI step 1: TriageAgent

Triage should:

- classify the message
- estimate confidence
- choose the route
- decide whether immediate human escalation is required

Allowed categories should stay small:

- `billing`
- `delivery`
- `refund`
- `policy`
- `account`
- `technical`
- `other`

Allowed routes should be:

- `specialist`
- `escalate`

Triage must not call business tools directly.

### AI step 2: SpecialistAgent

Specialist should:

- use company-specific knowledge
- inspect allowed local tool outputs
- draft the customer-safe reply
- decide whether the ticket can be resolved or must escalate

Specialist should operate inside clear constraints:

- only use facts from KB excerpts and tool outputs
- never invent policies or statuses
- never run tools outside the allowed tool list for the ticket category

### Human escalation

Human escalation should be represented by:

- `ticket.status = escalated`
- `ticket.escalation_reason`
- `ticket.handoff_note`

No separate LLM-based escalation agent is needed.

## Failure Rules

These rules should be hard-coded in the pipeline contract, not left vague.

Escalate automatically when:

- triage output is invalid JSON
- specialist output is invalid JSON
- category is unsupported
- required tool input is missing
- tool lookup returns ambiguous or missing data for an operational request
- confidence falls below threshold on an important step
- the customer requests a sensitive action
- the ticket is stuck in repeated unresolved turns

Recommended thresholds:

- triage confidence below `0.6` -> escalate
- specialist confidence below `0.7` -> escalate
- automatic resolution allowed only when specialist explicitly resolves and confidence is at least `0.8`

## Pages And Routes

### Overview page

Route:

- `GET /`

Purpose:

- frame the product as a support OS, not a chatbot
- show demo companies
- launch the widget
- link to the inbox
- link to a trace example

### Widget entry and conversation

Routes:

- `GET /widget/tickets/new`
- `POST /widget/tickets`
- `POST /widget/tickets/:ticket_id/messages`

Purpose:

- allow reviewer to choose one of the two demo companies
- create a customer and ticket
- submit an initial message
- continue the same ticket thread with follow-up messages

The widget should support both demo companies interactively.

### Inbox

Route:

- `GET /tickets`

Purpose:

- internal operational view of all tickets
- show company, customer, category, status, current layer, confidence, and last update

### Ticket detail

Route:

- `GET /tickets/:id`

Purpose:

- show ticket metadata
- show conversation thread
- show tool calls
- show handoff state if escalated
- show a compact trace section

### Dedicated trace page

Route:

- `GET /tickets/:id/trace`

Purpose:

- render the same `AgentRun` and `ToolCall` data in a cleaner timeline view

Important:

- this page must not introduce separate persistence
- it is only a second presentation of the same ticket trace data

## Suggested Models

Keep the schema small and demo-safe.

### Company

Fields:

- `name:string`
- `slug:string`
- `description:text`
- `support_email:string`

Associations:

- `has_many :knowledge_articles`
- `has_many :tickets`
- `has_many :business_records`

### Customer

Fields:

- `email:string`
- `name:string`

Associations:

- `has_many :tickets`

### Ticket

Fields:

- `company:references`
- `customer:references`
- `status:string`
- `category:string`
- `priority:string`
- `channel:string`
- `last_confidence:decimal`
- `current_layer:string`
- `summary:text`
- `escalation_reason:text`
- `handoff_note:text`

Suggested enums:

- `status`: `new`, `in_progress`, `resolved`, `escalated`
- `channel`: `widget`
- `current_layer`: `triage`, `specialist`, `human`

Associations:

- `belongs_to :company`
- `belongs_to :customer`
- `has_many :messages`
- `has_many :agent_runs`
- `has_many :tool_calls`

### Message

Fields:

- `ticket:references`
- `role:string`
- `content:text`

Suggested enums:

- `role`: `user`, `assistant`, `human`, `system`

Associations:

- `belongs_to :ticket`

### KnowledgeArticle

Fields:

- `company:references`
- `title:string`
- `slug:string`
- `category:string`
- `content:text`

Associations:

- `belongs_to :company`

### BusinessRecord

This replaces the older `Order`-specific idea.

It should be generic enough to support both companies while remaining simple.

Fields:

- `company:references`
- `record_type:string`
- `external_id:string`
- `customer_email:string`
- `status:string`
- `payload:json`

Examples:

- `aipassportphoto`: `record_type = "photo_request"`
- `nodes.garden`: `record_type = "node_deployment"`

Associations:

- `belongs_to :company`

### AgentRun

Stores each AI step.

Fields:

- `ticket:references`
- `agent_name:string`
- `status:string`
- `decision:string`
- `confidence:decimal`
- `input_snapshot:text`
- `output_snapshot:text`
- `reasoning_summary:text`

Expected `agent_name` values:

- `TriageAgent`
- `SpecialistAgent`
- optional synthetic handoff event if useful for rendering

Associations:

- `belongs_to :ticket`

### ToolCall

Stores local tool usage for trace visibility.

Fields:

- `ticket:references`
- `agent_run:references`
- `tool_name:string`
- `status:string`
- `input_payload:text`
- `output_payload:text`

Associations:

- `belongs_to :ticket`
- `belongs_to :agent_run, optional: true`

## Folder Structure

Keep it boring.

```text
app/
  controllers/
    home_controller.rb
    tickets_controller.rb
    traces_controller.rb
    widget/
      tickets_controller.rb
      messages_controller.rb
  models/
    company.rb
    customer.rb
    ticket.rb
    message.rb
    knowledge_article.rb
    business_record.rb
    agent_run.rb
    tool_call.rb
  services/
    support_pipeline.rb
    llm/
      client.rb
    agents/
      triage_agent.rb
      specialist_agent.rb
    tools/
      aipassportphoto/
        lookup_photo_request_tool.rb
        resend_asset_tool.rb
        refund_eligibility_tool.rb
        issue_receipt_tool.rb
      nodes_garden/
        lookup_deployment_tool.rb
        check_node_status_tool.rb
        retry_provisioning_tool.rb
        fetch_last_error_tool.rb
  presenters/
    ticket_presenter.rb
  views/
    home/
      index.html.erb
    tickets/
      index.html.erb
      show.html.erb
      _ticket_row.html.erb
      _status_badge.html.erb
      _trace_summary.html.erb
    traces/
      show.html.erb
    widget/
      tickets/
        new.html.erb
        create.turbo_stream.erb
        _form.html.erb
        _chat.html.erb
        _message.html.erb
      messages/
        create.turbo_stream.erb
  javascript/
    controllers/
      support_widget_controller.js
      auto_scroll_controller.js
```

## Routes

```ruby
Rails.application.routes.draw do
  root "home#index"

  resources :tickets, only: [:index, :show] do
    resource :trace, only: [:show], controller: "traces"
  end

  namespace :widget do
    resources :tickets, only: [:new, :create] do
      resources :messages, only: [:create]
    end
  end
end
```

## LLM Integration

Use a thin single-provider wrapper.

That wrapper should do only a few things:

- send prompt + input
- request structured JSON output
- normalize parse errors into a consistent failure result

Do not build a multi-provider abstraction.

Do not call the SDK directly from every service.

## Prompt Contracts

Keep prompts short, strict, and JSON-only.

### TriageAgent output

```json
{
  "category": "delivery",
  "priority": "normal",
  "route": "specialist",
  "confidence": 0.82,
  "needs_human_now": false,
  "reasoning_summary": "User is asking about a missing delivered asset."
}
```

### SpecialistAgent output

```json
{
  "reply": "I found your request and resent the asset to your email.",
  "resolve_ticket": true,
  "confidence": 0.88,
  "used_knowledge_articles": ["Delivery", "Refund Policy"],
  "used_tools": ["lookup_photo_request", "resend_asset"],
  "reasoning_summary": "The customer requested a missing file and the resend action succeeded."
}
```

## Tool Strategy

Tools should remain local and deterministic.

The important thing is not realism. The important thing is credible operational flow.

### Company 1: `aipassportphoto`

Likely tool names:

- `lookup_photo_request`
- `check_photo_job_status`
- `resend_asset`
- `refund_eligibility`
- `issue_receipt`

Typical support themes:

- missing file
- delayed generation
- refund edge case
- upload issue
- receipt request

### Company 2: `nodes.garden`

Likely tool names:

- `lookup_deployment`
- `check_node_status`
- `retry_provisioning`
- `fetch_last_error`

Typical support themes:

- delayed provisioning
- deployment still pending
- node unhealthy
- setup failed

Important design choice:

- tool names should be visibly different in traces for each company
- both companies can still use the same underlying `BusinessRecord` abstraction

## Seed Data

Seed only what is necessary to make the demo convincing.

### Companies

Use exactly 2 companies:

1. `AI Passport Photo`
2. `nodes.garden`

### Knowledge articles

Seed 4 to 6 per company.

`aipassportphoto` examples:

- Pricing
- Refund Policy
- Supported Countries
- Delivery Timing
- Upload Issues
- Privacy / Deletion

`nodes.garden` examples:

- Provisioning Lifecycle
- Deployment Delays
- Node Status Meanings
- Retry Policy
- Error Recovery Basics
- Billing / Credits Overview

### Business records

Seed only enough records to support the suggested prompt flows.

Examples:

- `aipassportphoto` photo request with delivered asset
- `aipassportphoto` photo request still processing
- `aipassportphoto` refund-ambiguous request
- `nodes.garden` deployment pending
- `nodes.garden` deployment healthy
- `nodes.garden` deployment failed with last error present

### Seeded tickets

Seed 4 to 6 tickets so the inbox is not empty.

At minimum include:

- knowledge auto-resolve
- tool-driven auto-resolve
- escalation case for `aipassportphoto`
- provisioning/status case for `nodes.garden`

## Suggested Demo Cases

### Case 1: FAQ auto-resolve

Company:

- `aipassportphoto`

User:

- `Do you support Canada passport photos?`

Expected flow:

- triage classifies `policy`
- specialist uses supported countries article
- ticket resolves

### Case 2: Tool-driven auto-resolve

Company:

- `aipassportphoto`

User:

- `I paid but did not receive my file. My email is anna@example.com`

Expected flow:

- triage classifies `delivery`
- specialist looks up the request and resends the asset
- ticket resolves

### Case 3: Human escalation

Company:

- `aipassportphoto`

User:

- `My photo was rejected by the embassy and I want a refund right now`

Expected flow:

- triage classifies `refund`
- specialist finds policy ambiguity
- ticket escalates with handoff note

### Case 4: Provisioning/status

Company:

- `nodes.garden`

User:

- `My node is still provisioning after 20 minutes`

Expected flow:

- triage classifies `technical`
- specialist checks deployment record and node status
- either resolves with a status explanation or escalates if the record is ambiguous

## Widget Behavior

The widget should support:

- company selector
- customer email input
- message input
- suggested demo prompts
- follow-up messages on the same ticket

The widget should feel like live chat, but it must remain ticket-backed.

Every new user message reruns the same bounded pipeline for that ticket.

## Trace Design

The trace should show:

- which AI step ran
- what it decided
- confidence
- what tools were called
- final resolution or escalation outcome

Use clear labels in the UI.

Good examples:

- `Classified request as delivery`
- `Loaded delivery policy`
- `Looked up photo request APP-1001`
- `Retried node provisioning`
- `Escalated to human reviewer`

The dedicated trace page should be cleaner than the ticket detail page, but should not expose any additional internal complexity.

## Implementation Advice

Keep prompts in Ruby constants or small prompt builders.

Store raw JSON outputs from both AI steps for debugging and trace rendering.

Do not overbuild abstractions.

The reviewer is more likely to reward:

- a coherent, working demo
- clear reasoning in the trace
- bounded and honest AI behavior

than a technically elaborate but shaky system.
