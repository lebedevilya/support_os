# SupportOS Progress

## Purpose

This file is a session handoff for the current SupportOS take-home project.

If the next session starts cold, read this file first, then read [PROPOSAL.md](/Users/ilyalebedev/projects/support_os/PROPOSAL.md) and [TECH.md](/Users/ilyalebedev/projects/support_os/TECH.md), and continue from the "Next Steps" section below.

## Project Goal

Build a small Rails + Hotwire demo for a portfolio-wide support operating system:

- one shared support layer for multiple companies
- ticket-backed customer conversations
- bounded AI workflow with `TriageAgent` -> `SpecialistAgent`
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

The core runtime is already in place:

- `SupportPipeline` orchestrates triage, specialist handling, ticket updates, trace storage, and outbound messages
- `Agents::TriageAgent` exists
- `Agents::SpecialistAgent` exists
- `LLM::Client` now uses `ruby_llm` as the model adapter while preserving the app-level workflow API
- fallback heuristic behavior exists when no LLM client is available
- triage can now answer FAQ-style questions directly from company public knowledge chunks
- text-only public page import and chunking services now exist

### Implemented data model

The schema already includes the planned demo entities:

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

### Seeded demo setup

Two demo companies are seeded:

- `AI Passport Photo`
- `nodes.garden`

Seed data already includes:

- knowledge articles per company
- imported public knowledge text per company
- generated chunks for retrieval
- mock business records
- sample seeded tickets
- representative demo scenarios

### Verified status

The test suite passes under the correct Ruby environment:

- command: `rbenv exec bundle exec bin/rails test`
- result: `13 runs, 100 assertions, 0 failures, 0 errors, 0 skips`

## What Matches The Plan

These planned requirements are already satisfied or mostly satisfied:

- Portfolio-wide framing instead of generic chatbot framing
- Two-company demo scope
- Ticket-centric conversation model
- Bounded two-step agent flow
- Human escalation represented as ticket state plus handoff note
- Dedicated trace persistence using `AgentRun` and `ToolCall`
- Mock/local business operations instead of real integrations
- Public knowledge retrieval at triage for FAQ-style questions
- Rails + Hotwire architecture with a small service-object core
- Seeded demo cases for review walkthroughs

## What Is Still Weak Or Incomplete

These are the main gaps between the current code and the intended demo quality.

### 1. Delivery flow is not honest enough

Current problem:

- the delivery specialist claims the asset was resent when a matching record exists
- no explicit resend tool call or verified resend state backs that claim

Why it matters:

- this breaks the "honest demo behavior" requirement
- it is the easiest thing for a reviewer to distrust

### 2. Guardrails are described but not enforced

Current problem:

- confidence thresholds exist in `TECH.md`
- the pipeline stores confidence but does not enforce escalation based on thresholds

Why it matters:

- the code currently tells a weaker story than the technical plan
- the demo claims bounded automation but still trusts weak outputs

### 3. Reviewer-facing operations UI is underpowered

Current problem:

- inbox does not show all planned operational fields like category and confidence
- ticket detail does not fully show escalation reason, handoff note, and tool output context
- trace page does not show enough payload detail to make the system feel operational

Why it matters:

- the backend captures more than the UI reveals
- the reviewer may miss the strongest part of the implementation

### 4. Widget is missing guided demo prompts

Current problem:

- the widget allows freeform input but does not present suggested prompts or example cases

Why it matters:

- the assignment asked for curated demo prompts
- guided prompts make the walkthrough reliable under time pressure

### 5. Admin and adapter work is still incomplete

Current problem:

- the public knowledge route exists in app code
- but MotorAdmin is not wired yet

Why it matters:

- the architecture is ahead of the back-office tooling

## Recommended Next Steps

Do these in this order.

### Step 1. Fix honesty in mock operations

Goal:

- stop claiming actions that were not actually simulated

Changes:

- update delivery handling so replies only describe verified state
- if we want a "resent asset" path, add an explicit mock tool such as `resend_asset`
- persist that tool call and show it in the trace

Expected outcome:

- the demo becomes defensible and more credible immediately

### Step 2. Enforce hard confidence guardrails in the pipeline

Goal:

- make the implementation match `TECH.md`

Changes:

- escalate when triage confidence is below `0.6`
- escalate when specialist confidence is below `0.7`
- only allow automatic resolution when specialist explicitly resolves and confidence is at least `0.8`
- add tests covering these cases

Expected outcome:

- the bounded-agent story becomes real instead of just documented

### Step 3. Upgrade the reviewer-facing UI

Goal:

- make the best parts of the system obvious in 30 seconds

Changes:

- inbox: show category and confidence
- ticket detail: show summary, escalation reason, handoff note, and tool calls
- trace page: show input/output payloads and clearer labels like "Mock tool call" or "Simulated lookup"

Expected outcome:

- the reviewer sees a support OS, not just a chat demo

### Step 4. Add guided demo prompts to the widget

Goal:

- make the demo reliable and fast to evaluate

Suggested prompts:

- `I paid but did not receive my file`
- `Do you support Canada passport photos?`
- `My photo was rejected by the embassy and I want a refund`
- `My node is still provisioning after 20 minutes`

Changes:

- render prompt buttons or cards in the widget UI
- prefill the message field when a prompt is selected
- optionally show suggested demo emails for seeded records

Expected outcome:

- the happy-path walkthrough becomes obvious and repeatable

### Step 5. Wire MotorAdmin

Goal:

- finish the admin side without changing the current workflow ownership

Changes:

- expose `Knowledge::Source`, `Knowledge::ManualEntry`, and `Knowledge::Chunk`
- add a manual import action if needed

Expected outcome:

- cleaner demo operations story

## Suggested Immediate Execution Plan

If resuming next session, start here:

1. Inspect `app/services/agents/specialist_agent.rb`
2. Fix the delivery response so it reflects actual mock state and explicit tool behavior
3. Add or update tests in `test/services/support_pipeline_test.rb`
4. Update `app/services/support_pipeline.rb` to enforce confidence thresholds
5. Add tests for low-confidence escalation paths
6. Update `app/views/tickets/index.html.erb`
7. Update `app/views/tickets/show.html.erb`
8. Update `app/views/traces/show.html.erb`
9. Add guided prompt UI to the widget views
10. Wire MotorAdmin if dependency install is allowed
11. Run `rbenv exec bundle exec bin/rails test`

## Key Files

These are the main files to inspect first next session:

- `PROPOSAL.md`
- `TECH.md`
- `db/seeds.rb`
- `app/services/support_pipeline.rb`
- `app/services/agents/triage_agent.rb`
- `app/services/agents/specialist_agent.rb`
- `app/services/public_knowledge/importer.rb`
- `app/services/public_knowledge/chunker.rb`
- `app/services/public_knowledge/retriever.rb`
- `app/services/llm/client.rb`
- `app/views/home/index.html.erb`
- `app/views/widget/tickets/new.html.erb`
- `app/views/widget/tickets/_form.html.erb`
- `app/views/tickets/index.html.erb`
- `app/views/tickets/show.html.erb`
- `app/views/traces/show.html.erb`
- `test/services/support_pipeline_test.rb`
- `test/services/public_knowledge/importer_test.rb`
- `test/services/public_knowledge/retriever_test.rb`
- `test/services/public_knowledge/support_pipeline_public_answer_test.rb`
- `test/integration/support_os_flow_test.rb`

## Environment Notes

- Intended Ruby version: `3.4.1`
- Verify with `rbenv`
- Use `rbenv exec bundle exec bin/rails test`, not plain `bin/rails test`
- There is already an unrelated local modification in `app/views/home/index.html.erb`; do not overwrite it blindly next session

## Definition Of "Good Enough To Submit"

The project is ready to submit when:

- mock operations are honest and clearly labeled
- confidence guardrails are enforced in code
- inbox and trace views clearly expose operational state
- widget has guided demo prompts
- public knowledge is seeded or manageable in a way the reviewer can inspect
- tests still pass
