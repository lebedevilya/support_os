# SupportOS Proposal

## Summary

SupportOS should not be presented as a generic support chatbot.

It should be presented as a support operating layer for an AI-native venture studio: one support platform that can serve multiple portfolio companies, route customer issues through AI support layers, keep a full trace of what happened, and escalate to a human only when the AI flow is not reliable enough.

The goal of this assignment is not to build a production-ready support platform. The goal is to show:

- strong product judgment
- ruthless scope control
- a believable agent-first support workflow
- clean architecture for a multi-company setup
- honest handling of demo data and mocked business operations

## Product Shape

The product should be a small Rails app with 4 core surfaces:

1. Overview page
2. Customer support widget
3. Internal support inbox
4. Ticket detail and agent trace page

### 1. Overview page

The reviewer should land on a simple overview page first.

That page should explain, in plain language:

- this is a portfolio-wide support operating system
- one platform can serve multiple startups
- customer conversations become structured tickets
- AI handles the first layers of support
- humans act as final fallback

It should link into the interactive parts of the demo:

- Open support widget
- View inbox
- View trace example

This matters because otherwise the reviewer may only see "a chat widget" and miss the actual point.

### 2. Customer support widget

The customer-facing entry point should feel like live chat, not like a static ticket form.

But under the hood, every interaction should still be stored as a ticket thread.

The widget should include:

- company selector
- customer email field
- message input
- transcript area
- suggested demo prompts

The widget should support a full chat feel, meaning the user can send follow-up messages.

Important constraint: this is still not a fully autonomous conversation engine. Every new user message should rerun the same bounded support flow against the same ticket.

### 3. Internal support inbox

The internal inbox should show the operational view of the system.

At minimum it should display:

- ticket id
- company
- category
- status
- current layer or owner
- confidence
- updated at

The inbox exists to show that the system is ticket-centric, not chat-centric.

### 4. Ticket detail and agent trace page

Each ticket should open into a detailed page that shows:

- the conversation thread
- the current status
- the final or draft AI response
- the reason for escalation, if any
- the agent trace for the ticket
- any mock tool calls and outputs

The trace page should be thin and reuse the same run data. It should not become a separate complex dashboard.

## Multi-Company Scope

The app should include 2 demo companies, not 1 and not 3.

Two is enough to prove the portfolio-company angle without wasting time on duplicated setup.

Suggested companies:

- AI Passport Photo
- Stablecoin invoicing tool

Each company should have:

- its own knowledge base articles
- its own sample support cases
- its own mock business data

The support platform itself should stay shared.

That is the core thesis: one support OS for many small startups.

## Support Flow

The runtime model should be a constrained live-agent system with 3 visible support layers:

1. Triage
2. Specialist
3. Human

### Triage

Triage should:

- classify the message into a small fixed set of categories
- estimate confidence
- decide whether the issue can stay in the AI flow
- decide which knowledge and tools are relevant

The allowed categories should stay small, for example:

- billing
- delivery
- refund
- policy
- account

### Specialist

Specialist should:

- load company-specific knowledge
- inspect relevant mock records
- use only the tools allowed for the category
- draft the next customer response
- either resolve the issue or pass it onward

### Human

Human is the fallback layer.

Tickets should escalate here when:

- confidence is too low
- the user asks for a sensitive action
- tool output is ambiguous
- the model output is invalid
- the case is outside the known support envelope

This is important because the demo should show judgment, not AI theater.

## AI Approach

The demo should use a constrained live-agent approach.

That means:

- the LLM is used live
- the LLM can make bounded decisions
- the system does not give the LLM unlimited freedom

Guardrails should be explicit:

- fixed category list
- fixed tool set
- tool access restricted by category
- structured outputs
- automatic escalation on parse failure or uncertainty

This is the right compromise.

It preserves real AI behavior without making the entire demo depend on perfect model behavior.

## Demo Data and Demo Honesty

The app should use seeded demo companies, seeded knowledge articles, seeded customer scenarios, and mocked business records.

That is fine.

What is not fine is pretending that mocked data is real production evidence.

So the UI should be explicit about demo boundaries. Use labels like:

- Demo company
- Sample ticket
- Mock order lookup
- Simulated tool call

The system should support both:

- curated demo prompts for reliable walkthroughs
- freeform customer input for exploratory use

This is the right mix.

The reviewer gets something interactive, but the important paths are still reliable.

## Demo Cases

Seed 4 to 6 good support scenarios, not 12.

That is enough to demonstrate coverage without bloating the build.

Examples:

- I paid but did not receive my file
- My photo was rejected, can I get a refund?
- Do you support Canada?
- I used the wrong email
- I need an invoice or receipt

Each scenario should have:

- a company
- a category
- relevant mock records
- allowed tools
- an expected resolved or escalated outcome

## Tools and Mock Operations

Do not build real external integrations for this assignment.

Instead, expose a few believable mock tools backed by local data, for example:

- lookup_order
- resend_asset
- refund_eligibility
- issue_receipt
- check_processing_status

These tools should look operational in the UI, but remain clearly demo-safe and local.

## Recommended Stack

Use the stack that maximizes execution speed and coherence:

- Rails
- Hotwire / Turbo
- Stimulus
- SQLite or PostgreSQL
- service objects for the support layers

There is no need for:

- React
- websockets
- Redis
- real async infrastructure
- vector databases
- omnichannel integrations

## Data Model

Keep the schema very small.

Suggested models:

- Company
- Customer
- Ticket
- Message
- KnowledgeArticle
- AgentRun
- ToolCall
- MockOrder

Optional only if clearly useful:

- Escalation
- SupportPolicy

## Positioning

The project should be framed like this:

"I intentionally built a support operating layer for a venture studio rather than a generic chatbot. The system is designed for multiple portfolio companies, ticket-based workflows, agent-first support handling, explicit auditability, and human fallback when AI confidence drops."

That framing is stronger than "I built a support bot."

## What To Avoid

Do not spend time on:

- auth
- email sync
- Slack integration
- production deployment concerns
- advanced RAG
- complex analytics
- fake enterprise breadth

The reviewer will learn more from a tight, honest, well-executed demo than from a larger but shakier system.

## Final Recommendation

Build SupportOS as a narrow but convincing multi-company support demo:

- overview page for framing
- live chat-style widget for customer interaction
- inbox for operational visibility
- ticket detail page with conversation, tool calls, and trace
- 3 support layers: Triage, Specialist, Human
- 2 demo companies
- seeded demo scenarios
- mocked but explicit business tools
- live LLM behavior inside hard constraints

That is the strongest balance of:

- relevance to Code & State
- believable product thinking
- technical clarity
- achievable scope for a take-home assignment
