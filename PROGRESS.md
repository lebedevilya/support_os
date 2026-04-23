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
- no-LLM fallback paths have been removed; both agents always assume an LLM client is available
- triage can answer FAQ-style questions directly from `Knowledge::Chunk` retrieval
- public knowledge import, same-domain link discovery, chunking, and retrieval services now exist
- public-knowledge replies are LLM-composed from retrieved chunks only; triage does not get tool access
- public-knowledge citations are now conditional and only appended when the cited URL is one of the retrieved supporting sources
- widget conversations now run asynchronously through `SupportPipelineJob` with Turbo Streams instead of blocking on the request cycle
- widget shows a loading spinner while the job runs, updates via ActionCable broadcast (Turbo Stream) when done
- a Stimulus polling fallback fires every 3 seconds via `GET /widget/tickets/:id/chat` in case the WebSocket broadcast is missed
- `kamal-proxy response_timeout` is set to `3600` to prevent idle WebSocket disconnections
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
- demo deployment wiring now exists through Kamal with a single-server SQLite production path and persistent `storage/` volume mounting
- agent prompts are extracted into frozen constants in dedicated `Triage::Prompts` and `Specialist::Prompts` modules
- shared normalizer helpers (`normalized_category`, `normalized_priority`, etc.) live in `Agents::Shared::Normalizers`
- `Triage::KnowledgeAnswerer` is a dedicated service for LLM knowledge synthesis and grounding validation
- `RubyLLM.configure` runs once at boot in an initializer; `use_new_acts_as = true` silences the legacy API deprecation warning
- 80-question regression sweep has been run against production; knowledge seeds updated based on results

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
- the embedded company widget header now shows the active customer email once the conversation starts
- Kamal config now resolves locally and targets the existing DigitalOcean host with persistent SQLite storage
- the target server is reachable over SSH and has Docker available
- the only deploy blocker seen in this session was GHCR authentication during `docker login`

Latest full-suite result:

- command: `bin/rails test`
- result: `79 runs, 628 assertions, 0 failures, 0 errors, 0 skips`

### Deployment state

Production is live and verified at `http://147.135.78.29`.

- Kamal deploys to a single DigitalOcean server via `kamal deploy`
- SQLite with persistent `/home/debian/apps/support_os/storage` volume
- `kamal proxy reboot` is required after `response_timeout` changes in `config/deploy.yml`
- registry: `ghcr.io/lebedevilya/support_os` (GHCR, authenticated)
- polling fallback verified end-to-end: ticket created via test API, first poll returned the reply Turbo Stream within 3 seconds

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

### 1. Human operator UX is thin

- the customer-facing waiting state is clear inside the widget
- but the internal side after manual takeover is still minimal: no assignee model, no inbox split between AI-handled and human-owned tickets, no strong work queue behavior
- the ownership model is correct, but the operator UX stops short of a believable support console

### 2. Imported knowledge is noisy

- curated `Knowledge::ManualEntry` records handle the most important FAQ paths well
- but imported public knowledge still has low-signal chunks in places; source titles are sometimes ugly or duplicative
- no curation pass has been done over imported pages; the curated layer carries the weight

### 3. Tag taxonomy is shallow

- tags are persisted and surfaced in the inbox, but auto-assignment is still basic
- some fallback tags come from category/status/rule names rather than a controlled taxonomy
- no admin workflow exists for merging near-duplicate tags; they accumulate silently

## Recommended Next Steps

### 1. Polish the human support console

- consider an explicit inbox split or queue view for human-owned tickets
- improve trace/ticket labeling so the operator can instantly see what automation already did vs. what is now manual

### 2. Curate imported knowledge

- review imported chunks for both companies
- remove low-value or duplicative chunks via MotorAdmin or a seed cleanup pass
- make sure all high-value FAQ paths have a curated `Knowledge::ManualEntry` counterpart

### 3. Tighten tag quality

- expose tags on ticket detail more prominently
- tighten the LLM tag prompt so output stays within a controlled set
- consider a simple admin merge/consolidate workflow in MotorAdmin

### 4. Tighten knowledge-answer boundaries (optional)

- reconsider whether `KNOWLEDGE_MIN_SCORE = 2` is strong enough
- prefer specialist or escalation over weak “not found in public info” answers when retrieval confidence is low

## Suggested Immediate Execution Plan

If resuming next session, start here:

1. Verify the live demo flows end-to-end: widget, specialist tool path, escalation, human reply
2. Polish the human-owned ticket UX in the inbox
3. Run a curated knowledge cleanup pass for both companies
4. Run `bin/rails test` to confirm 79 runs still pass

## Key Files

These are the main files to inspect first next session:

- `OVERVIEW.md` — concise orientation guide
- `PROPOSAL.md` — product framing and goals
- `TECH.md` — technical design
- `PROGRESS.md` — this file
- `db/seeds.rb`
- `app/services/support_pipeline.rb`
- `app/services/agents/triage_agent.rb`
- `app/services/agents/triage/prompts.rb`
- `app/services/agents/triage/knowledge_answerer.rb`
- `app/services/agents/specialist_agent.rb`
- `app/services/agents/specialist/prompts.rb`
- `app/services/agents/shared/normalizers.rb`
- `app/services/support_rule_matcher.rb`
- `app/models/support_rule.rb`
- `app/views/tickets/index.html.erb`
- `app/views/tickets/show.html.erb`
- `app/views/traces/show.html.erb`
- `app/services/public_knowledge/retriever.rb`
- `app/services/llm/client.rb`
- `config/initializers/ruby_llm.rb`
- `app/jobs/support_pipeline_job.rb`
- `app/views/widget/tickets/_chat.html.erb`
- `app/javascript/controllers/processing_poll_controller.js`
- `config/deploy.yml`
- `test/services/support_pipeline_test.rb`
- `test/integration/support_os_flow_test.rb`

## Environment Notes

- Ruby `3.4.1` — verify with `rbenv`
- use `bin/dev` during UI work so `tailwindcss:watch` keeps `app/assets/builds/tailwind.css` up to date
- `db:seed` performs live site imports; network access is required for realistic knowledge seeding
- SQLite can throw `database is locked` under parallel test workers; `bin/rails test` (single-process) is reliable
- deploy: `kamal deploy` then `kamal proxy reboot` if `config/deploy.yml` proxy settings changed

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
