# SupportOS Progress

## Purpose

This file is the current handoff for the SupportOS take-home project.

If the next session starts cold, read this file first, then read [PROPOSAL.md](/Users/ilyalebedev/projects/support_os/PROPOSAL.md) and [TECH.md](/Users/ilyalebedev/projects/support_os/TECH.md), and continue from the "Next Steps" section below.

## Project Goal

Build a small Rails + Hotwire demo for a portfolio-wide support operating system:

- one shared support layer for multiple companies
- ticket-backed customer conversations
- bounded AI workflow with `TriageAgent -> SpecialistAgent`
- human escalation as the final fallback
- visible trace of agent decisions and mock tool usage

This is not supposed to be a production support platform. It is supposed to show product judgment, scope control, believable agentic support, and honest demo behavior.

## Current State

### Implemented surfaces

The four planned product surfaces exist:

- Overview page: `/`
- Customer widget: `/widget/tickets/new`
- Internal inbox: `/tickets`
- Ticket detail + dedicated trace page: `/tickets/:id` and `/tickets/:id/trace`

### Implemented architecture

The core runtime is in place:

- `SupportPipeline` orchestrates triage, specialist handling, ticket updates, trace storage, and outbound messages
- `Agents::TriageAgent` exists and now checks DB-backed support rules before knowledge retrieval
- `Agents::SpecialistAgent` exists
- `LLM::Client` uses `ruby_llm` while preserving the app-level workflow API
- fallback heuristic behavior still exists when no LLM client is available
- triage can answer FAQ-style questions directly from `Knowledge::Chunk` retrieval
- public knowledge import, same-domain link discovery, chunking, and retrieval services now exist
- public-knowledge replies are LLM-composed from retrieved chunks only; triage does not get tool access
- public-knowledge citations are now conditional and only appended when the cited URL is one of the retrieved supporting sources
- widget conversations now run asynchronously through `SupportPipelineJob` with Turbo Streams instead of blocking on the request cycle
- MotorAdmin is mounted at `/admin` behind HTTP Basic auth backed by Rails credentials

### Implemented data model

The schema now includes the main demo entities plus editable support routing:

- `Company`
- `Customer`
- `Ticket`
- `Message`
- `AgentRun`
- `ToolCall`
- `KnowledgeArticle`
- `Knowledge::Source`
- `Knowledge::ManualEntry`
- `Knowledge::Chunk`
- `BusinessRecord`
- `SupportRule`

### Seeded demo setup

Two demo companies are seeded:

- `AI Passport Photo`
- `nodes.garden`

Seed data already includes:

- company records
- knowledge articles
- support rules
- public knowledge source records imported from live sites
- generated chunks from imported pages
- mock business records
- seeded tickets for the main walkthroughs

The seed flow now uses `PublicKnowledge::SiteImporter` instead of handwritten `Knowledge::Source` snippets.

### Verified live knowledge import

`db:seed` was run after the importer changes with live network access.

Current imported public sources:

- `aipassportphoto`
  - `https://www.aipassportphoto.co/`
  - `https://www.aipassportphoto.co/contact`
  - `https://www.aipassportphoto.co/guarantee`
  - `https://www.aipassportphoto.co/privacy`
  - `https://www.aipassportphoto.co/terms`
  - current chunk count observed after seed: `66`
- `nodes-garden`
  - `https://nodes.garden/`
  - `https://nodes.garden/dashboard`
  - `https://nodes.garden/pages/about`
  - `https://nodes.garden/pages/commerce_stripe_disclosure`
  - `https://nodes.garden/pages/crypto_node`
  - `https://nodes.garden/pages/faq`
  - `https://nodes.garden/pages/partners`
  - `https://nodes.garden/pages/privacy_policy`
  - `https://nodes.garden/pages/terms_of_service`
  - current chunk count observed after seed: `97`

### Verified status

The most recently verified flows:

- widget first message renders immediately and shows assistant loading state while `SupportPipelineJob` runs
- widget follow-up now renders the new user message immediately and streams the assistant reply later
- widget close action now resolves the conversation in place via Turbo Stream
- public-knowledge replies no longer attach a generic link to every answer

Most recently re-run tests:

- command: `bin/rails test test/integration/support_os_flow_test.rb test/jobs/support_pipeline_job_test.rb test/services/public_knowledge/support_pipeline_public_answer_test.rb`
- result: `13 runs, 115 assertions, 0 failures, 0 errors, 0 skips`

Last previously recorded broader suite result:

- command: `rbenv exec bundle exec bin/rails test`
- result: `23 runs, 142 assertions, 0 failures, 0 errors, 0 skips`

## What Matches The Plan

These planned requirements are already satisfied or mostly satisfied:

- portfolio-wide framing instead of generic chatbot framing
- two-company demo scope
- ticket-centric conversation model
- bounded two-step agent flow
- human escalation represented as ticket state plus handoff note
- dedicated trace persistence using `AgentRun` and `ToolCall`
- mock/local business operations instead of real integrations
- editable DB-backed triage overrides via `SupportRule`
- public knowledge seeded from live company sites instead of placeholder snippets
- same-domain crawl for support/legal pages during site import
- knowledge-answer routing is stricter than before and no longer triggers on any incidental chunk hit
- knowledge answers now remain in `awaiting_customer` and do not auto-close the ticket
- widget chat now behaves like a real async support flow instead of blocking on the LLM request
- customer can explicitly close the conversation with `This solved my issue`
- Rails + Hotwire architecture with a small service-object core
- seeded demo cases for reviewer walkthroughs

## What Is Still Weak Or Incomplete

These are the main gaps between the current code and the intended demo quality.

### 1. Confidence guardrails are still documented but not enforced

Current problem:

- confidence thresholds exist in `TECH.md`
- the pipeline stores confidence but does not enforce escalation based on thresholds

Why it matters:

- the code still tells a weaker story than the technical plan
- the demo claims bounded automation but still trusts weak outputs

### 2. Delivery flow is not honest enough

Current problem:

- the delivery specialist still claims the asset was resent when a matching record exists
- no explicit resend tool call or verified resend state backs that claim

Why it matters:

- this breaks the honest-demo requirement
- it is an easy thing for a reviewer to distrust

### 3. Trace linkage and reviewer-facing UI are underpowered

Current problem:

- `ToolCall` records are not clearly linked to a specific `AgentRun`
- inbox does not show category and confidence
- ticket detail does not fully show summary, escalation reason, handoff note, and tool output context
- trace page does not show enough payload detail to feel operational

Why it matters:

- the backend captures more than the UI reveals
- the reviewer may miss the strongest part of the implementation

### 4. Widget and admin are still rough

Current problem:

- the core chat loop works now, but the widget still does not show guided demo prompts or suggested seeded emails
- MotorAdmin is mounted, but the knowledge and support-rule workflow has not been curated for a reviewer walkthrough

Why it matters:

- guided walkthroughs should be obvious
- the back office should support the product story, not just exist

### 5. Triage still contains fallback heuristics for non-rule paths

Current problem:

- the embassy refund path is now DB-backed, but `supported_country?`, `missing_asset?`, and `provisioning_status?` are still hardcoded fallback heuristics
- `OPERATIONAL_TERMS` for blocking knowledge answers is also heuristic logic in code

Why it matters:

- this is acceptable for the deadline, but it is still a compromise
- if time permits, more of the deterministic routing story should move into rules instead of code

## Recommended Next Steps

Do these in this order.

### Step 1. Enforce hard confidence guardrails in the pipeline

Goal:

- make the implementation match `TECH.md`

Changes:

- escalate when triage confidence is below `0.6`
- escalate when specialist confidence is below `0.7`
- only allow automatic resolution when specialist explicitly resolves and confidence is at least `0.8`
- add tests covering these cases

Expected outcome:

- the bounded-agent story becomes real instead of just documented

### Step 2. Fix honesty in mock operations

Goal:

- stop claiming actions that were not actually simulated

Changes:

- update delivery handling so replies only describe verified state
- if we want a "resent asset" path, add an explicit mock tool such as `resend_asset`
- persist that tool call and show it in the trace

Expected outcome:

- the demo becomes defensible and more credible immediately

### Step 3. Upgrade the reviewer-facing UI and trace

Goal:

- make the best parts of the system obvious in 30 seconds

Changes:

- inbox: show category and confidence
- ticket detail: show summary, escalation reason, handoff note, and tool calls
- trace page: show input/output payloads and clearer labels such as `Mock tool call`, `Knowledge answer`, or `Human escalation rule`
- attach tool calls to the relevant agent run
- make it obvious in the UI when a reply came from public knowledge vs specialist handling vs human escalation

Expected outcome:

- the reviewer sees a support OS, not just a chat demo

### Step 4. Add guided demo prompts and curate admin

Goal:

- make the walkthrough reliable and the back office understandable

Changes:

- add prompt buttons or cards to the widget
- prefill message input from selected prompts
- optionally show suggested demo emails for seeded records
- curate MotorAdmin around `Knowledge::` models and `SupportRule`

Expected outcome:

- the happy-path walkthrough becomes obvious and repeatable

### Step 5. Tighten knowledge-answer boundaries

Goal:

- stop answering from weak or irrelevant retrieved content even when retrieval returns a chunk

Changes:

- reconsider whether `KNOWLEDGE_MIN_SCORE = 2` is strong enough
- avoid public-knowledge answers when the retrieved content does not actually answer the question
- prefer specialist or escalation over vague “not found in public info” answers when retrieval confidence is weak
- add tests around pricing, edge-case policy questions, and irrelevant legal-page retrieval

Expected outcome:

- triage feels more trustworthy and less eager

### Optional cleanup. Reduce remaining hardcoded triage heuristics

Goal:

- further reduce code-path special cases if there is still time

Changes:

- consider moving supported-country, delivery, and provisioning routing hints into additional `SupportRule` data
- consider replacing the current `OPERATIONAL_TERMS` block with a more explicit rule or classifier boundary

Expected outcome:

- a cleaner operating-layer story, but this is lower priority than guardrails, honesty, and UI

## Suggested Immediate Execution Plan

If resuming next session, start here:

1. Add tests for low-confidence triage escalation
2. Add tests for low-confidence specialist escalation and no-auto-resolve below `0.8`
3. Enforce the confidence thresholds in `app/services/support_pipeline.rb`
4. Fix delivery honesty with an explicit resend tool path
5. Link `ToolCall` records to `AgentRun`
6. Upgrade inbox, ticket detail, and trace views
7. Tighten knowledge-answer boundaries for weak or irrelevant retrieval hits
8. Add widget demo prompts and suggested emails
9. Curate MotorAdmin around `Knowledge::` models and `SupportRule`
10. Run `rbenv exec bundle exec bin/rails test`

## Key Files

These are the main files to inspect first next session:

- `PROPOSAL.md`
- `TECH.md`
- `PROGRESS.md`
- `db/seeds.rb`
- `app/services/support_pipeline.rb`
- `app/services/agents/triage_agent.rb`
- `app/services/agents/specialist_agent.rb`
- `app/services/support_rule_matcher.rb`
- `app/services/public_knowledge/importer.rb`
- `app/services/public_knowledge/link_discoverer.rb`
- `app/services/public_knowledge/site_importer.rb`
- `app/services/public_knowledge/chunker.rb`
- `app/services/public_knowledge/retriever.rb`
- `app/services/llm/client.rb`
- `app/jobs/support_pipeline_job.rb`
- `app/views/widget/tickets/new.html.erb`
- `app/views/widget/tickets/_form.html.erb`
- `app/views/widget/tickets/_chat.html.erb`
- `app/views/widget/messages/create.turbo_stream.erb`
- `app/views/widget/tickets/close.turbo_stream.erb`
- `app/views/tickets/index.html.erb`
- `app/views/tickets/show.html.erb`
- `app/views/traces/show.html.erb`
- `test/services/support_pipeline_test.rb`
- `test/services/support_pipeline_support_rule_test.rb`
- `test/services/support_rule_matcher_test.rb`
- `test/services/public_knowledge/importer_test.rb`
- `test/services/public_knowledge/link_discoverer_test.rb`
- `test/services/public_knowledge/site_importer_test.rb`
- `test/services/public_knowledge/retriever_test.rb`
- `test/services/public_knowledge/support_pipeline_public_answer_test.rb`
- `test/integration/support_os_flow_test.rb`

## Environment Notes

- intended Ruby version: `3.4.1`
- verify with `rbenv`
- use `rbenv exec bundle exec bin/rails test`, not plain `bin/rails test`
- `db:seed` now performs live site imports, so network access is required for realistic knowledge seeding
- SQLite can throw `database is locked` if multiple test files are run in parallel from separate processes; serial runs are reliable

## Definition Of "Good Enough To Submit"

The project is ready to submit when:

- hardcoded embassy-refund triage logic is replaced by editable support rules
- public knowledge is seeded from meaningful live website content
- public-knowledge answering does not hijack obvious operational requests
- public-knowledge answers only cite supporting sources when they actually support the answer
- widget chat feels responsive and conversational instead of blocking on model latency
- mock operations are honest and clearly labeled
- confidence guardrails are enforced in code
- inbox and trace views clearly expose operational state
- widget has guided demo prompts
- tests still pass
