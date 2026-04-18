# Public Knowledge Triage Design

## Goal

Add a company-scoped public knowledge layer so first-line support can answer FAQ-style questions directly from imported website text and manual support notes, without sending those questions through the operational specialist flow.

## Why This Change Exists

The current implementation is too narrow. Triage mostly routes by hardcoded keywords and cannot answer basic public questions such as:

- "How long does it take?"
- "Do you support Canada?"
- "What does the guarantee cover?"
- "How can I contact support?"

That is the wrong behavior for this product. Public support questions should be answered immediately from company-specific public information. Specialist handling should be reserved for operational or account-specific requests that need mock tools, business records, or human escalation.

## Product Behavior

Every incoming customer message still creates a normal ticket and message thread.

Triage should then run in this order:

1. Search the company's public knowledge and manual support knowledge.
2. If the message is answerable from that knowledge with high confidence, generate a direct customer-safe reply and stop there.
3. If the request appears operational, ambiguous, sensitive, or unsupported by public knowledge, continue through the existing specialist or escalation path.

This keeps the system ticket-centric while making first-line support materially smarter.

## Scope

### In scope

- Company-scoped imported public support pages
- Extracted text-only storage from those pages
- Chunking imported text for retrieval
- Manual admin-managed custom knowledge entries
- Triage-first retrieval over imported and manual knowledge
- FAQ-style answers generated from retrieved chunks
- MotorAdmin-based admin workflow for import and manual entries
- `ruby_llm` as the LLM adapter for structured triage/specialist output

### Out of scope

- Background jobs
- automatic refresh or scheduled re-import
- embeddings or vector database
- storing raw HTML
- rewriting the app around gem-native agent abstractions
- custom internal admin UI beyond MotorAdmin

## Data Model

The existing `KnowledgeArticle` model is not enough. It should no longer be the only knowledge representation.

The new design should split support knowledge into explicit source types.

### Knowledge::Source

Represents one imported public page for one company.

Suggested fields:

- `company_id`
- `url`
- `title`
- `source_kind`
- `status`
- `extracted_text`
- `imported_at`
- `last_error`

Notes:

- `source_kind` can stay simple, for example `website_page`
- `status` can be `pending`, `imported`, or `failed`
- `extracted_text` stores normalized plain text only
- raw HTML should not be stored

### Knowledge::Chunk

Represents one retrieval chunk derived from a public source or manual entry.

Suggested fields:

- `company_id`
- `public_knowledge_source_id` nullable
- `manual_knowledge_entry_id` nullable
- `content`
- `position`
- `token_estimate`

Notes:

- chunks must store text exactly as imported or manually entered, with light normalization only
- chunking exists to reduce prompt size and make retrieval explainable

### Knowledge::ManualEntry

Represents manually authored support information added via admin.

Suggested fields:

- `company_id`
- `title`
- `content`
- `status`

Notes:

- manual entries are separate from imported public content
- imported website text should remain read-only after import
- if support needs extra guidance, add a manual entry rather than editing imported text

## Import Pipeline

Import is manual-only for the demo.

Admin workflow:

1. Create a `Knowledge::Source` with URL and company.
2. Trigger a manual import action.
3. Fetch the page.
4. Extract visible text only.
5. Normalize whitespace and remove irrelevant boilerplate where reasonable.
6. Save plain extracted text into `extracted_text`.
7. Chunk the text into `Knowledge::Chunk` records.
8. Mark import success or failure.

Important constraint:

- the importer must extract text information only
- it must not persist raw HTML or page structure
- the goal is support context, not page archiving

## Retrieval Strategy

Keep retrieval simple and local.

Recommended approach:

- normalize the incoming message
- score chunks for the ticket's company using straightforward text matching
- choose the top relevant chunks
- pass those chunks into triage as public knowledge context

No embeddings are needed for this demo.

The retrieval only needs to be good enough for:

- FAQ questions
- turnaround time
- guarantee/refund basics
- supported countries
- contact and policy questions

## Triage Design

The triage stage should be extended, not replaced.

### New triage responsibilities

- detect whether the message can be answered from public/manual knowledge
- answer directly when public knowledge is sufficient
- continue to specialist only for operational or tool-backed requests

### Triage output contract

The current triage output should grow to include a knowledge-answer route.

Suggested route values:

- `knowledge_answer`
- `specialist`
- `escalate`

Suggested behavior:

- `knowledge_answer`: create assistant reply directly from triage
- `specialist`: continue to specialist
- `escalate`: escalate to human

### Confidence rules

Public knowledge answers should require strong confidence.

Suggested rules:

- if retrieval finds weak or noisy context, do not guess
- if the message asks for an account-specific action, do not answer from public knowledge
- if the user combines FAQ and operational intent, route to specialist or escalate based on the operational part

Examples:

- "How long does it take?" -> knowledge answer
- "Do you support Canada?" -> knowledge answer
- "Where can I contact you?" -> knowledge answer
- "I paid but did not receive my file" -> specialist
- "My photo was rejected by the embassy, I want a refund" -> escalate

## LLM Usage

Use `ruby_llm` as the adapter for model calls.

Do not rebuild the app around `ruby_llm`.

The correct boundary is:

- application workflow stays in `SupportPipeline`, `TriageAgent`, and `SpecialistAgent`
- `ruby_llm` handles model invocation and structured responses

This keeps the business logic explicit and explainable while removing the current hand-rolled HTTP integration.

## Admin Design

MotorAdmin is sufficient for the demo.

Admin tasks that should be supported:

- create public knowledge source records
- trigger manual page import
- inspect extracted text
- inspect generated chunks
- add manual knowledge entries

This is enough to prove that company support memory can be populated from public web data plus operator-authored additions.

## UI / Demo Impact

This feature should improve the demo in visible ways:

- public FAQ-style questions get good answers immediately
- tickets still exist for traceability and follow-up questions
- traces can show that triage answered from public knowledge
- support feels more like a real first-line system and less like a narrow scripted demo

The reviewer should be able to see that:

- companies have imported public knowledge
- triage uses that knowledge directly
- specialist handling is reserved for operational issues

## Risks And Guardrails

### Risk: over-answering from weak retrieval

Mitigation:

- require explicit confidence threshold
- only answer from top relevant chunks
- escalate or continue when unsure

### Risk: public text pollutes operational support

Mitigation:

- public knowledge route exists only for FAQ-style questions
- operational/account-sensitive requests bypass public-answer behavior

### Risk: import quality varies by site

Mitigation:

- keep importer simple
- extract visible text only
- support manual knowledge entries to patch gaps

## Implementation Direction

Implementation should proceed in this order:

1. Add the new knowledge models and schema
2. Build manual import service with text extraction and chunking
3. Wire MotorAdmin for CRUD and manual import
4. Extend triage to retrieve chunks first
5. Add knowledge-answer route to the support pipeline
6. Replace the current low-level LLM client with a `ruby_llm` adapter
7. Add tests for public FAQ answers and operational fallthrough

## Success Criteria

This feature is successful when:

- a company can import text from public support pages manually
- raw HTML is not stored
- imported content is chunked and retrievable
- triage can answer FAQ-style questions directly from that knowledge
- specialist remains responsible only for operational/tool-backed cases
- tickets are still created for every conversation
- tests cover the new route and still pass
