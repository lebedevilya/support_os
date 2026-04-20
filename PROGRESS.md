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

The main product surfaces now exist:

- Overview page: `/`
- Company landing pages: `/companies/:slug`
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
- company landing pages now embed the support widget as a bottom-right floating shell instead of forcing users onto a separate widget-only page
- `SupportPipeline` now enforces confidence guardrails instead of only recording confidence values
- delivery fallback replies now describe verified state only and no longer claim an asset resend happened without an explicit simulated action
- deterministic triage routing and public-knowledge blocker boundaries now live in `SupportRule`, not in ad hoc string heuristics inside `TriageAgent`
- ticket tagging is now implemented with `acts-as-taggable-on`
- ticket tags are assigned automatically by agent outputs and rule matches, with missing tags created automatically in the DB
- the inbox now supports filtering by company, status, and tag
- the inbox now shows aggregate counts by company, status, tag, and total ticket count
- inbox pagination is now implemented with `pagy`
- MotorAdmin is mounted at `/admin` behind HTTP Basic auth backed by Rails credentials
- specialist-created `ToolCall` records are now backfilled onto the corresponding `SpecialistAgent` run when the pipeline persists the run
- curated `Knowledge::ManualEntry` records are now part of the public-knowledge strategy instead of relying only on imported website text
- manual-entry chunk indexing now lives in a dedicated `Knowledge::ManualEntryIndexer` service rather than hidden model logic
- public-knowledge retrieval now stays generic in code while preferring curated manual entries over noisy imported chunks

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
- `ActsAsTaggableOn::Tag`
- `ActsAsTaggableOn::Tagging`

### Seeded demo setup

Two demo companies are seeded:

- `AI Passport Photo`
- `nodes.garden`

Seed data already includes:

- company records
- knowledge articles
- curated manual knowledge entries for the highest-value FAQ answers
- support rules
- starter tag records for common demo cases
- public knowledge source records imported from live sites
- generated chunks from imported pages
- mock business records
- seeded lookup and action-tool specialist cases for both companies
- seeded tickets for the main walkthroughs

The seed flow now uses `PublicKnowledge::SiteImporter` instead of handwritten `Knowledge::Source` snippets.

### Public knowledge import

`db:seed` attempts to import live public pages for both companies.

Important caveat:

- import success depends on network access at seed time
- when the network is blocked, the seed still completes, but imported public pages will be missing until `bin/rails db:seed` is re-run with network access
- curated manual knowledge still seeds locally and continues to support the most important FAQ-style cases

### Verified status

The most recently verified flows:

- widget first message renders immediately and shows assistant loading state while `SupportPipelineJob` runs
- widget follow-up now renders the new user message immediately and streams the assistant reply later
- widget close action now resolves the conversation in place via Turbo Stream
- public-knowledge replies no longer attach a generic link to every answer
- clicking a company on `/` opens its branded landing page
- each company page now shows an embedded floating support widget launcher in the bottom-right corner
- inbox ticket rows are clickable with hover affordance
- ticket detail and trace pages now include back navigation links
- low-confidence triage now escalates before specialist runs
- low-confidence specialist outcomes now escalate even if a reply was drafted
- delivery replies no longer claim a resend when only a lookup tool was used
- the widget now enforces a valid customer email before a ticket can be created
- `OPERATIONAL_TERMS` has been removed; public-knowledge blocking is now rule-driven through `SupportRule`
- `supported_country?`, `missing_asset?`, and `provisioning_status?` have been removed from `TriageAgent`
- automatic ticket tagging now works across triage, specialist, knowledge-answer, and support-rule paths
- the inbox now supports company/status/tag filtering plus count summaries and pagination
- once support replies manually, subsequent customer follow-ups stay on the human-owned ticket path and do not trigger `SupportPipelineJob`
- ticket replies from the human support page now redirect back to the reply section instead of jumping to the top
- inbox company/status/tag summaries now render inside collapsible dropdown sections instead of dumping every item inline
- manual takeover is now visible in inbox, ticket detail, and trace views
- ticket detail now surfaces tags and clearer ownership state for human-owned tickets
- trace and ticket pages now use clearer agent source labels instead of raw source keys
- specialist tool calls created during pipeline execution are now linked to the persisted `SpecialistAgent` run instead of remaining unlinked
- internal UI now uses operator-facing status labels such as `Needs support`, `Waiting on support`, and `Waiting on customer`
- curated manual knowledge now outranks noisy imported pages in retrieval without hardcoding company-specific phrases in code
- manual entries now auto-index into chunks through a dedicated service so retrieval stays in sync with curated content
- specialist can now complete explicit mock action tools in addition to lookup tools
- AI Passport Photo now supports a demo `resend_download_link` action after request lookup
- nodes.garden now supports a demo `reboot_node` action after deployment lookup
- the dedicated trace page now renders as a timeline with inline lookup/action tool steps and collapsible raw payloads
- company widgets now expose one-click seeded scenario prompts on a fresh conversation
- scenario prompts now prefill the seeded email and message and submit immediately on a new chat
- scenario prompts are intentionally hidden once a conversation is in progress
- closing a conversation now offers an in-widget `Start a new conversation` path with the same company preselected
- the company-scoped new-ticket frame now stays scrollable after closing and reopening a chat
- escalated or human-owned widget conversations now show a customer-facing waiting state instead of exposing raw operator handoff wording

Most recently re-run tests:

- command: `bin/rails test test/integration/support_os_flow_test.rb`
- result: `20 runs, 274 assertions, 0 failures, 0 errors, 0 skips`

Latest full-suite result:

- command: `PARALLEL_WORKERS=1 bin/rails test`
- result: `60 runs, 494 assertions, 0 failures, 0 errors, 0 skips`

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
- deterministic triage routing for the current demo cases is now DB-backed through `SupportRule`
- public-knowledge blocking for operational/sensitive requests is now DB-backed through `SupportRule`
- knowledge answers now remain in `awaiting_customer` and do not auto-close the ticket
- widget chat now behaves like a real async support flow instead of blocking on the LLM request
- customer can explicitly close the conversation with `This solved my issue`
- the demo now feels more like a real portfolio product because company cards open branded landing pages with embedded support
- the internal inbox now behaves like a usable operations surface with filtering, tag summaries, and pagination
- the ticket model now carries editable tag data instead of forcing support classification to live only in code
- manual takeover is now explicit: once support replies, the ticket becomes human-owned and automation stops for later customer follow-ups
- tool traces are now more honest because specialist tool calls are linked to the actual persisted specialist run
- curated manual knowledge now exists for the key seeded FAQ paths, and retrieval prefers that curated data over noisier imported text
- Rails + Hotwire architecture with a small service-object core
- seeded demo cases for reviewer walkthroughs

## What Is Still Weak Or Incomplete

These are the main gaps between the current code and the intended demo quality.

### 1. Human support remains visually clear for customers, but operator workflow is still thin

Current problem:

- the customer-facing waiting state is now much clearer inside the widget
- but the internal human-support side is still thin after takeover: there is still no explicit assignee model, inbox split, or stronger human work queue behavior

Why it matters:

- the ownership model is correct, but the operator UX still stops short of a believable support console

### 2. Knowledge quality is still only partially curated

Current problem:

- curated manual entries now exist for key FAQs, which is a major improvement
- but imported public knowledge is still noisy in places and source titles are still ugly or low-signal
- retrieval is better, but there is still no explicit source-quality curation pass over imported pages and chunks

Why it matters:

- the system will only feel trustworthy if the knowledge it uses is obviously clean and intentional
- right now the curated layer exists, but the imported layer still needs cleanup to avoid dragging answer quality down

### 3. Automatic tagging is still basic

Current problem:

- tags are now persisted and surfaced, but the automatic assignment is still shallow
- some fallback tags are inferred from category/status/rule names rather than a stronger controlled taxonomy
- there is no admin UX yet for consolidating near-duplicate tags or auditing low-quality tag assignment

Why it matters:

- tags are only useful if they stay clean
- without curation, the tag layer can drift into noisy metadata instead of becoming a durable operational tool

### 4. Triage still has one coarse fallback path

Current problem:

- deterministic rule-based routing and rule-based knowledge blocking are now DB-backed
- the remaining fallback path is still broad: if no support rule, no safe public-knowledge answer, and no LLM route applies, triage escalates with a generic "outside the demo cases" outcome

Why it matters:

- this is acceptable for the deadline, but it still leaves the non-LLM fallback story coarse
- if time permits, the remaining fallback could become more explicit or better-scoped

## Recommended Next Steps

Do these in this order.

### Step 1. Tighten knowledge quality

Goal:

- make public-knowledge answers more consistently useful

Changes:

- review imported chunks for the seeded companies
- remove obvious low-value or duplicative chunks
- clean up weak source titles and noisy pages where possible
- make sure the most important public questions map cleanly to curated manual entries or strong source pages

Expected outcome:

- triage knowledge answers feel more intentional and less noisy

### Step 2. Improve tag operations

Goal:

- make tags a real support ops primitive instead of passive metadata

Changes:

- expose tags clearly on ticket detail
- add a simple admin workflow for merging or cleaning tags
- tighten the LLM prompt and fallback taxonomy so tag output stays stable

Expected outcome:

- the reviewer sees a support OS, not just a chat demo

### Step 3. Finish the human support console

Goal:

- make the manually owned ticket flow feel more like an actual support tool internally

Changes:

- add stronger queue behavior for human-owned tickets
- consider an explicit "assigned/unassigned" or "owned by support" distinction if that helps the demo
- keep improving trace/ticket labeling so the operator can instantly tell what automation already did and what is now manual

Expected outcome:

- the reviewer sees a believable human-support workflow after escalation instead of just a reply box

### Step 4. Add guided showcase polish where it helps the walkthrough

Changes:

- keep the showcase docs and seeded scenarios aligned
- consider adding a lightweight scenario picker or index page outside the widget if the reviewer needs a more guided start
- curate MotorAdmin around `Knowledge::` models and `SupportRule`

Expected outcome:

- the walkthrough stays reliable without hiding the freeform product shape

### Step 4. Tighten knowledge-answer boundaries

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

- tighten the remaining coarse fallback behavior if there is still time

Changes:

- consider whether the generic non-LLM fallback escalation should be split into a few clearer bounded cases
- consider whether more reviewer-facing explanation should be stored when the fallback path is used

Expected outcome:

- a cleaner operating-layer story, but this is lower priority than guardrails, honesty, and UI

## Suggested Immediate Execution Plan

If resuming next session, start here:

1. Link `ToolCall` records to `AgentRun` consistently
2. Tighten the ticket/trace UI so linked vs unlinked operational steps are obvious
3. Add an explicit `resend_asset` tool path only if the demo truly needs to claim resend behavior
4. Tighten knowledge-answer boundaries for weak or irrelevant retrieval hits
5. Add widget demo prompts and suggested emails
6. Curate MotorAdmin around `Knowledge::` models and `SupportRule`
7. Run `rbenv exec bundle exec bin/rails test`

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
- `app/models/support_rule.rb`
- `app/views/tickets/index.html.erb`
- `app/views/tickets/show.html.erb`
- `app/views/traces/show.html.erb`
- `app/services/public_knowledge/importer.rb`
- `app/services/public_knowledge/link_discoverer.rb`
- `app/services/public_knowledge/site_importer.rb`
- `app/services/public_knowledge/chunker.rb`
- `app/services/public_knowledge/retriever.rb`
- `app/services/llm/client.rb`
- `app/jobs/support_pipeline_job.rb`
- `app/controllers/companies_controller.rb`
- `app/views/companies/show.html.erb`
- `app/views/widget/tickets/new.html.erb`
- `app/views/widget/tickets/_form.html.erb`
- `app/views/widget/tickets/_chat.html.erb`
- `app/views/widget/tickets/_embedded_shell.html.erb`
- `app/views/widget/messages/create.turbo_stream.erb`
- `app/views/widget/tickets/close.turbo_stream.erb`
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
- use `bin/dev` during UI work so `tailwindcss:watch` keeps `app/assets/builds/tailwind.css` up to date
- `db:seed` now performs live site imports, so network access is required for realistic knowledge seeding
- after the latest rule-system change, `db:migrate` is required for `support_rules.blocks_public_knowledge`
- SQLite can throw `database is locked` if multiple test files are run in parallel from separate processes; serial runs are reliable

## Definition Of "Good Enough To Submit"

The project is ready to submit when:

- hardcoded embassy-refund triage logic is replaced by editable support rules
- public knowledge is seeded from meaningful live website content
- public-knowledge answering does not hijack obvious operational requests
- public-knowledge answers only cite supporting sources when they actually support the answer
- widget chat feels responsive and conversational instead of blocking on model latency
- company landing pages make the demo feel like a real product surface instead of a widget sandbox
- confidence guardrails are enforced in code
- delivery replies do not claim operational actions that were never simulated
- mock operations are honest and clearly labeled
- inbox and trace views clearly expose operational state
- widget has guided demo prompts
- tests still pass
