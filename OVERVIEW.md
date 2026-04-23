# SupportOS Overview

A support operating layer for a two-company venture studio portfolio, built as a Rails + Hotwire take-home demo. The thesis is one shared support platform that handles AI triage, specialist resolution, and human escalation for multiple portfolio companies.

## Live Demo

Production: `http://147.135.78.29`

Two demo companies:
- **AI Passport Photo** — `/companies/aipassportphoto`
- **nodes.garden** — `/companies/nodes-garden`

Each company page has an embedded support widget in the bottom-right corner with one-click scenario prompts.

## Key Surfaces

| Surface | Route | Purpose |
|---|---|---|
| Overview | `/` | Frames the product; links to companies, inbox, and traces |
| Company page | `/companies/:slug` | Branded landing page with embedded support widget |
| Widget | `/widget/tickets/new` | Customer-facing chat; standalone URL |
| Inbox | `/tickets` | Internal operational view with company/status/tag filters |
| Ticket detail | `/tickets/:id` | Conversation thread, agent outputs, tool calls |
| Trace | `/tickets/:id/trace` | Timeline view of all agent decisions and tool steps |
| Admin | `/admin` | MotorAdmin for `Knowledge::`, `SupportRule`, and `BusinessRecord` |

## Support Pipeline

Every customer message runs through `SupportPipeline`:

```
SupportPipelineJob
  → SupportPipeline
      → SupportRuleMatcher       (deterministic DB-backed routing)
      → TriageAgent              (LLM: classify, confidence, route)
          → KnowledgeAnswerer    (LLM: answer from retrieved chunks)
      → SpecialistAgent          (LLM: tool use, draft reply, resolve/escalate)
```

Processing is async via `SolidQueue`. The widget shows a loading spinner while the job runs, then updates via ActionCable broadcast (Turbo Stream). A polling fallback fires every 3 seconds in case the WebSocket is unavailable.

## Agent Architecture

```
app/services/agents/
  shared/normalizers.rb          # shared parsing helpers for both agents
  triage/
    prompts.rb                   # frozen prompt constants
    knowledge_answerer.rb        # LLM knowledge synthesis + grounding check
  specialist/
    prompts.rb                   # frozen prompt constants + dynamic action prompt
  triage_agent.rb
  specialist_agent.rb
```

Both agents always assume an LLM client is available. No non-LLM fallback paths exist.

## Knowledge Strategy

Public knowledge is imported from live company sites via `PublicKnowledge::SiteImporter`. Curated `Knowledge::ManualEntry` records exist for high-value FAQ paths and rank higher than imported chunks during retrieval. All knowledge is chunked and scored by keyword overlap at retrieval time.

`SupportRule` records in the DB control:
- deterministic category routing
- knowledge-answer blocking for operational/sensitive topics
- human handoff triggers

## Data Model

```
Company → Ticket → Message
                 → AgentRun → ToolCall
Customer → Ticket
Knowledge::Source → Knowledge::Chunk
Knowledge::ManualEntry → Knowledge::Chunk
SupportRule
BusinessRecord
```

## Running Locally

```bash
bin/setup
bin/dev          # starts Rails + Tailwind watcher
bin/rails db:seed
```

Tests:
```bash
bin/rails test
# 79 runs, 628 assertions, 0 failures
```

## Deployment

Kamal to a single DigitalOcean server (`147.135.78.29`) with SQLite + persistent storage volume.

```bash
kamal deploy
kamal proxy reboot   # required after response_timeout changes in deploy.yml
```

Registry: `ghcr.io/lebedevilya/support_os`

## Known Gaps

1. **Human operator UX is thin** — no assignee model, no queue split between new and human-owned tickets
2. **Imported knowledge is noisy** — curated manual entries carry the important FAQ paths, but the imported chunk layer still has low-signal content
3. **Tag taxonomy is shallow** — tags are auto-assigned but not curated; near-duplicates accumulate over time
