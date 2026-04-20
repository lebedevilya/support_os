# nodes.garden Showcases

These cases are meant to show the same three support layers on the infrastructure side of the demo: triage-only knowledge, specialist lookup/action work, and human handoff.

## 1. Deployment lifecycle

- Seeded customer email: `lifecycle@example.com`
- Prompt: `What states can a deployment go through?`
- Expected path: `Triage knowledge`
- Expected tools called: none
- Expected outcome: the assistant answers from public/manual knowledge about provisioning, syncing, healthy, and failed states

## 2. Billing basics

- Seeded customer email: `billing@example.com`
- Prompt: `How does billing work?`
- Expected path: `Triage knowledge`
- Expected tools called: none
- Expected outcome: the assistant answers from public/manual knowledge and the trace stays on triage only

## 3. Provisioning status lookup

- Seeded customer email: `operator@example.com`
- Prompt: `My node is still provisioning after 20 minutes`
- Expected path: `Triage -> Specialist`
- Expected tools called: `lookup_deployment`
- Expected outcome: specialist finds the seeded deployment, reports the provisioning state, and the trace shows one lookup tool under the specialist step

## 4. Reboot node

- Seeded customer email: `operator@example.com`
- Prompt: `Reboot my node`
- Expected path: `Triage -> Specialist`
- Expected tools called: `lookup_deployment`, `reboot_node`
- Expected outcome: specialist confirms the reboot action completed, the deployment moves to `rebooting`, and the trace shows an `Action completed` tool step

## 5. Explicit human request

- Seeded customer email: `human@example.com`
- Prompt: `Connect me to a human in this chat`
- Expected path: `Human handoff`
- Expected tools called: none
- Expected outcome: the explicit-human-handoff check escalates before knowledge or specialist work, and the trace records a handoff path instead of automation
