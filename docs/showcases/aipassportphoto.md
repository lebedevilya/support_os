# AI Passport Photo Showcases

These cases are meant to show all three support layers in the demo: triage-only knowledge answers, specialist lookup/action work, and human escalation.

## 1. UK visa support coverage

- Seeded customer email: `review@example.com`
- Prompt: `Can I make a picture for UK visa?`
- Expected path: `Triage knowledge`
- Expected tools called: none
- Expected outcome: the assistant answers from public company knowledge that UK support exists and the trace shows a single `Triage step`

## 2. Turnaround time

- Seeded customer email: `timing@example.com`
- Prompt: `How long does it take?`
- Expected path: `Triage knowledge`
- Expected tools called: none
- Expected outcome: the assistant answers from public/manual knowledge about normal delivery timing and the ticket stays `Waiting on customer`

## 3. Delivery status lookup

- Seeded customer email: `anna@example.com`
- Prompt: `What is the status of my photo request?`
- Expected path: `Triage -> Specialist`
- Expected tools called: `lookup_photo_request`
- Expected outcome: specialist finds the seeded business record, replies from the lookup result, and the trace shows a specialist step with one lookup tool

## 4. Resend download link

- Seeded customer email: `sara@example.com`
- Prompt: `I did not receive my file, resend the download link`
- Expected path: `Triage -> Specialist`
- Expected tools called: `lookup_photo_request`, `resend_download_link`
- Expected outcome: specialist confirms the link was resent, the ticket stays automated, and the trace shows lookup first and then an `Action completed` step

## 5. Embassy refund dispute

- Seeded customer email: `refund@example.com`
- Prompt: `My photo was rejected by the embassy and I want a refund right now`
- Expected path: `Human handoff`
- Expected tools called: none
- Expected outcome: triage escalates immediately, the ticket becomes `Needs support`, and the trace records the handoff reason
