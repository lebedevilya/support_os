# SupportOS

SupportOS is a Rails + Hotwire demo of a shared support layer for multiple startups.

Instead of giving each company its own isolated chatbot or inbox, this app models support as one operational system that can:

- serve multiple companies from the same backend
- store every conversation as a ticket
- route requests through bounded AI support layers
- escalate safely to a human when needed

The demo currently serves two portfolio companies:

- `AI Passport Photo`
- `nodes.garden`

## What This Repo Demonstrates

- A support widget embedded on branded company pages
- A ticket-backed conversation model instead of a freeform chat log
- A constrained AI workflow with explicit routing and escalation
- An internal inbox for reviewing and handling tickets
- A trace view that makes agent behavior inspectable

## How It Works

Each customer message enters a bounded support pipeline:

1. The message is stored on a `Ticket`.
2. `TriageAgent` decides whether the request can be answered from knowledge, should be routed to a specialist, or should be handed to a human immediately.
3. `SpecialistAgent` performs limited operational work with mock tools and drafts the next safe customer reply.
4. If the request is ambiguous, sensitive, or low-confidence, the system escalates instead of bluffing.

This is deliberate. The app is not trying to be an unrestricted agent. It is trying to behave like a support system with explicit boundaries.

## Architecture

### Agents

- `TriageAgent`
  Decides what kind of request the customer made and whether the system should answer, route, or escalate.
- `SpecialistAgent`
  Handles operational follow-up using bounded tools and business records.

### Knowledge Sources

- Public website knowledge
  Imported from company sites and chunked for retrieval.
- Manual knowledge entries
  Curated, support-safe answers for the most important FAQ paths.
- `SupportRule` records
  Database-backed boundaries that control what the system is allowed to do.

### Operational Tools

The demo includes bounded mock tools such as:

- `lookup_photo_request`
- `resend_download_link`
- `lookup_deployment`
- `reboot_node`

These tools exist to show operational workflows without pretending the system has unlimited access.

### LLM Runtime

- OpenAI via `ruby_llm`
- used inside a constrained workflow, not as a general-purpose agent shell

## Product Surfaces

- Overview page that frames the product as a shared support OS
- Company landing pages with an embedded support widget
- Internal inbox for all tickets
- Ticket detail page
- Trace page for agent decisions and tool activity

## Widget Features

- One-click seeded demo scenarios for a fresh conversation
- Async follow-up messages
- Human handoff waiting states
- Restart-after-close flow
- Customer email shown in the company widget header after the conversation starts

Example scenarios only appear for a new chat. Once a conversation is active, the widget removes that noise.

## Why The Trace Matters

Most AI demos hide the interesting part. This one does not.

The trace view persists and exposes:

- customer messages
- agent decisions
- confidence values
- handoff reasons
- lookup steps
- mock tool activity

That makes the system inspectable as an operations product, not just a chat UI.

## Local Setup

### Requirements

- Ruby / Bundler matching the app
- SQLite

### Install

```bash
bundle install
bin/rails db:setup
```

### Run

```bash
bin/dev
```

### Test

```bash
bin/rails test
```

If you prefer the explicit database flow instead of `db:setup`:

```bash
bin/rails db:create db:migrate db:seed
```

## Deployment

This repo includes a Kamal deployment setup for a single server.

Production uses persistent SQLite files in `storage/`, so the deploy relies on a mounted volume at `/rails/storage`.

Current deployment assumptions:

- image registry is `ghcr.io`
- the server has registry credentials available
- the SQLite storage volume is mounted persistently

Without that volume, production data will not survive container restarts.

## Positioning

This project is a demo of a portfolio-wide support operating system:

- one support layer across multiple products
- bounded AI instead of fake autonomy
- ticketing and traceability instead of black-box chat
- clear escalation paths instead of confident nonsense
