# Public Knowledge Triage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add text-only imported public knowledge and manual knowledge entries so triage can answer FAQ-style questions directly before specialist handling.

**Architecture:** Introduce explicit company knowledge source and chunk models, a manual import service that extracts visible text and chunks it, and a retrieval step inside triage. Keep the existing `SupportPipeline` and agent service objects, but add a new `knowledge_answer` route and swap the low-level OpenAI client to a `ruby_llm` adapter.

**Tech Stack:** Rails 8, Active Record, Minitest, Nokogiri/open-uri or Net::HTTP for text extraction, MotorAdmin, ruby_llm

---

### Task 1: Add Knowledge Models And Schema

**Files:**
- Create: `db/migrate/*_create_public_knowledge_sources.rb`
- Create: `db/migrate/*_create_manual_knowledge_entries.rb`
- Create: `db/migrate/*_create_knowledge_chunks.rb`
- Create: `app/models/knowledge/source.rb`
- Create: `app/models/knowledge/manual_entry.rb`
- Create: `app/models/knowledge/chunk.rb`
- Modify: `app/models/company.rb`
- Test: `test/models/` as needed or service-level coverage

- [ ] Write failing tests for associations/usage through services
- [ ] Run targeted tests to verify failure
- [ ] Add migrations and models
- [ ] Run tests again

### Task 2: Build Manual Import And Chunking

**Files:**
- Create: `app/services/public_knowledge/importer.rb`
- Create: `app/services/public_knowledge/chunker.rb`
- Test: `test/services/public_knowledge/importer_test.rb`

- [ ] Write failing importer tests for text extraction, plain-text storage, and chunk creation
- [ ] Run targeted tests to verify failure
- [ ] Implement importer/chunker with text-only extraction
- [ ] Run targeted tests to pass

### Task 3: Add Retrieval Layer

**Files:**
- Create: `app/services/public_knowledge/retriever.rb`
- Test: `test/services/public_knowledge/retriever_test.rb`

- [ ] Write failing retrieval tests for FAQ-style matching and company scoping
- [ ] Run targeted tests to verify failure
- [ ] Implement simple scoring and top-chunk selection
- [ ] Run targeted tests to pass

### Task 4: Extend Triage And Pipeline

**Files:**
- Modify: `app/services/agents/triage_agent.rb`
- Modify: `app/services/support_pipeline.rb`
- Test: `test/services/support_pipeline_test.rb`

- [ ] Write failing tests for `knowledge_answer` route and follow-through message creation
- [ ] Run targeted tests to verify failure
- [ ] Implement retrieval-aware triage and pipeline handling
- [ ] Run targeted tests to pass

### Task 5: Replace Low-Level LLM Adapter

**Files:**
- Modify: `Gemfile`
- Modify: `app/services/llm/client.rb`
- Test: `test/services/llm_client_test.rb`

- [ ] Write failing adapter tests around configuration and response handling
- [ ] Run targeted tests to verify failure
- [ ] Implement `ruby_llm`-backed adapter without changing app workflow ownership
- [ ] Run targeted tests to pass

### Task 6: Seed Public Knowledge

**Files:**
- Modify: `db/seeds.rb`

- [ ] Add imported/manual knowledge data for both demo companies
- [ ] Keep demo-safe and text-only

### Task 7: Add Admin Access

**Files:**
- Modify: `Gemfile`
- Modify: `config/routes.rb`
- Modify: config/initializer files as needed

- [ ] Add MotorAdmin
- [ ] Expose knowledge source, chunk, and manual entry records
- [ ] Keep admin flow manual-only for the demo

### Task 8: Verify End To End

**Files:**
- Modify: `PROGRESS.md`

- [ ] Run targeted tests during each step
- [ ] Run full suite: `rbenv exec bundle exec bin/rails test`
- [ ] Update `PROGRESS.md` with the new architecture and remaining gaps
