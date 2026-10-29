# Fruit-System

The Fruit System: the operating system for a Kenyan fruit stall or kiosk. Buying at dawn, selling by the piece, the
heap, the kilo and the cup, beating spoilage, M-Pesa recorded by itself, and *Msaidizi wa Matunda*, an assistant the
owner talks to in Kiswahili or English. Built by Naim Automation Systems Co.

No client has signed yet: a fruit stall is the next local business the founder is approaching. Everything that belongs
to one client is a `[[placeholder]]` in the master prompt, filled in from the business profile after the kickoff.
Prices are never invented. (In the company repo the same files live in `clients/fruit-system/`.)

## What is here

| File | What it is |
|---|---|
| `MASTERPROMPT.md` | The complete build directive: sales by piece, heap, kilo and cup; buying by the crate; stock by batch with freshness; spoilage and markdowns; tomorrow's buying plan; debts and suppliers; orders; M-Pesa; the owner's own assistant with voice; design; tests; phases; go-live. Start here. |
| `AGENTS.md`, `CLAUDE.md` | How an agent works in this repo: small verified passes, evidence in `status.md`, a push after every pass. |
| `supabase/naim/001_framework.sql` | The company's framework for the shared client database (naim-local): schema, helpers and the standard row-level security. Copied from the company repo on every publish; never edit it here. |
| `docs/company/` | The company standards this build follows: Hermes per-client isolation, naim-local, M-Pesa automatic prompts. Copied on every publish. |

## Start the build

The demo can be built now. Open the repo in Claude Code and say: *"Read MASTERPROMPT.md and build it, starting with
phase P0."* Everything runs in mock mode with no keys, using the fictional demo stall in Appendix A, which is also what
the founder shows a prospect. When a fruit seller signs the *Fruit System Agreement*, the founder fills the
`[[placeholders]]` and section 2 from the signed agreement, and the go-live runbook (section 17) makes the system his.
