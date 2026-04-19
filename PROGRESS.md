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
- `Agents::TriageAgent` exists
- `Agents::SpecialistAgent` exists
- `LLM::Client` uses `ruby_llm` while preserving the app-level workflow API
- fallback heuristic behavior exists when no LLM client is available
- triage can answer FAQ-style questions directly from `Knowledge::Chunk` retrieval
- public knowledge import, chunking, and retrieval services exist
- MotorAdmin is mounted at `/admin` behind HTTP Basic auth backed by Rails credentials

### Implemented data model

The schema already includes the main demo entities:

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

- company records
- knowledge articles
- public knowledge source records and generated chunks
- mock business records
- seeded tickets for the main walkthroughs

### Verified status

The test suite currently passes under the correct Ruby environment:

- command: `rbenv exec bundle exec bin/rails test`
- result: `14 runs, 102 assertions, 0 failures, 0 errors, 0 skips`

The git worktree was clean at the start of this session.

## What Matches The Plan

These planned requirements are already satisfied or mostly satisfied:

- portfolio-wide framing instead of generic chatbot framing
- two-company demo scope
- ticket-centric conversation model
- bounded two-step agent flow
- human escalation represented as ticket state plus handoff note
- dedicated trace persistence using `AgentRun` and `ToolCall`
- mock/local business operations instead of real integrations
- Rails + Hotwire architecture with a small service-object core
- seeded demo cases for reviewer walkthroughs

## What Is Still Weak Or Incomplete

These are the main gaps between the current code and the intended demo quality.

### 1. Triage still contains hardcoded policy paths

Current problem:

- `Agents::TriageAgent` still has hardcoded checks like `embassy_refund?`, `supported_country?`, `missing_asset?`, and `provisioning_status?`
- those rules are not editable by humans and do not fit the "support operating layer" story

Why it matters:

- this is the wrong abstraction for a demo about agent-managed operations
- the reviewer should be able to see that routing policy can be adjusted without code changes

### 2. Knowledge exists, but the seeded content is too thin to be useful

Current problem:

- `Knowledge::Source` and `Knowledge::Chunk` exist, but the current seeds use short handwritten snippets in `db/seeds.rb`
- the imported knowledge does not yet feel like real public support context from company websites
- retrieval can technically work, but the underlying content is not strong enough to justify the feature

Why it matters:

- the current state oversells the knowledge layer
- if the reviewer inspects `/admin` or the trace, the knowledge system looks shallow

### 3. Public-knowledge answering is too eager

Current problem:

- triage resolves from public knowledge whenever retrieval returns any chunk
- there is no real confidence gate or operational-intent filter on that path

Why it matters:

- mixed or operational requests can be incorrectly treated as FAQ resolutions
- this weakens the bounded-agent story

### 4. Guardrails are documented but not enforced

Current problem:

- confidence thresholds exist in `TECH.md`
- the pipeline stores confidence but does not enforce escalation based on thresholds

Why it matters:

- the code currently tells a weaker story than the technical plan
- the demo claims bounded automation but still trusts weak outputs

### 5. Delivery flow is not honest enough

Current problem:

- the delivery specialist claims the asset was resent when a matching record exists
- no explicit resend tool call or verified resend state backs that claim

Why it matters:

- this breaks the honest-demo requirement
- it is an easy thing for a reviewer to distrust

### 6. Trace linkage and reviewer-facing UI are underpowered

Current problem:

- `ToolCall` records are not clearly linked to a specific `AgentRun`
- inbox does not show category and confidence
- ticket detail does not fully show summary, escalation reason, handoff note, and tool output context
- trace page does not show enough payload detail to feel operational

Why it matters:

- the backend captures more than the UI reveals
- the reviewer may miss the strongest part of the implementation

### 7. Widget and admin are still rough

Current problem:

- the widget does not show guided demo prompts or suggested seeded emails
- MotorAdmin is mounted, but the knowledge and future support-rule workflow has not been curated

Why it matters:

- guided walkthroughs should be obvious
- the back office should support the product story, not just exist

## Recommended Next Steps

Do these in this order.

### Step 1. Replace hardcoded triage rules with DB-backed support rules

Goal:

- move deterministic routing overrides out of `Agents::TriageAgent` and into editable data

Changes:

- add a `SupportRule` model
- support both global rules and company-specific rules
- keep scope narrow: routing overrides only, not a generic policy engine
- add a matcher service that returns normalized triage results from active rules
- seed at least the current embassy-refund escalation path as a rule
- expose the new rule records in MotorAdmin

Expected outcome:

- the support-routing story becomes more credible and easier to demonstrate

### Step 2. Replace weak knowledge seeds with website-derived public knowledge

Goal:

- make the knowledge layer worth having

Changes:

- import meaningful text from the real public pages for both demo companies
- keep the imported content text-only and chunked
- seed richer `Knowledge::Source` and `Knowledge::Chunk` data from those pages instead of short manual snippets
- keep manual entries available only for small operator-added gaps

Expected outcome:

- FAQ retrieval is grounded in believable company knowledge instead of placeholder text

### Step 3. Tighten triage behavior around knowledge answers

Goal:

- stop public knowledge from resolving requests too aggressively

Changes:

- check support-rule overrides before knowledge retrieval
- require stronger retrieval quality before `knowledge_answer`
- avoid resolving obvious operational or sensitive requests from public knowledge alone
- add tests for FAQ resolution versus operational fallthrough

Expected outcome:

- triage behaves more like a bounded first-line system and less like a keyword shortcut

### Step 4. Enforce hard confidence guardrails in the pipeline

Goal:

- make the implementation match `TECH.md`

Changes:

- escalate when triage confidence is below `0.6`
- escalate when specialist confidence is below `0.7`
- only allow automatic resolution when specialist explicitly resolves and confidence is at least `0.8`
- add tests covering these cases

Expected outcome:

- the bounded-agent story becomes real instead of just documented

### Step 5. Fix honesty in mock operations

Goal:

- stop claiming actions that were not actually simulated

Changes:

- update delivery handling so replies only describe verified state
- if we want a "resent asset" path, add an explicit mock tool such as `resend_asset`
- persist that tool call and show it in the trace

Expected outcome:

- the demo becomes defensible and more credible immediately

### Step 6. Upgrade the reviewer-facing UI and trace

Goal:

- make the best parts of the system obvious in 30 seconds

Changes:

- inbox: show category and confidence
- ticket detail: show summary, escalation reason, handoff note, and tool calls
- trace page: show input/output payloads and clearer labels such as `Mock tool call`, `Knowledge answer`, or `Human escalation rule`
- attach tool calls to the relevant agent run

Expected outcome:

- the reviewer sees a support OS, not just a chat demo

### Step 7. Add guided demo prompts and curate admin

Goal:

- make the walkthrough reliable and the back office understandable

Changes:

- add prompt buttons or cards to the widget
- prefill message input from selected prompts
- optionally show suggested demo emails for seeded records
- curate MotorAdmin around `Knowledge::` models and `SupportRule`

Expected outcome:

- the happy-path walkthrough becomes obvious and repeatable

## Suggested Immediate Execution Plan

If resuming next session, start here:

1. Add tests for a new `SupportRule` matcher and triage override path
2. Add the `SupportRule` schema, model, and matcher service
3. Replace hardcoded triage methods with rule evaluation
4. Seed global and company-specific support rules
5. Audit the real company websites and replace thin knowledge seeds with imported text
6. Add tests for stronger public-knowledge routing behavior
7. Enforce confidence guardrails in `app/services/support_pipeline.rb`
8. Fix delivery honesty with an explicit resend tool path
9. Link `ToolCall` records to `AgentRun`
10. Upgrade inbox, ticket detail, and trace views
11. Add widget demo prompts and suggested emails
12. Curate MotorAdmin around `Knowledge::` models and `SupportRule`
13. Run `rbenv exec bundle exec bin/rails test`

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
- `config/routes.rb`
- `config/initializers/motor_admin.rb`
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

- intended Ruby version: `3.4.1`
- verify with `rbenv`
- use `rbenv exec bundle exec bin/rails test`, not plain `bin/rails test`

## Definition Of "Good Enough To Submit"

The project is ready to submit when:

- hardcoded triage policy paths are replaced by editable support rules
- public knowledge is seeded from meaningful website content
- mock operations are honest and clearly labeled
- confidence guardrails are enforced in code
- inbox and trace views clearly expose operational state
- widget has guided demo prompts
- tests still pass
