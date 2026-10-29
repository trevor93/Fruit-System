# AGENTS.md — how to build the Fruit System here (Claude Code reads CLAUDE.md, which says the same)

1. `git pull --ff-only`. Read `MASTERPROMPT.md` whole (the product truth), then `status.md` → **RESUME HERE** and
   `DECISIONS.md`. If `status.md` does not exist yet, you are starting: create `status.md` and `DECISIONS.md` exactly as
   MASTERPROMPT section 3 says, before any code.
2. Work in **passes**: one small verified change → `npm run check` green (from phase P0 on) → update `status.md` (tick
   with evidence: the command you ran and what it printed; move RESUME HERE) → commit `<type>: <what changed>`
   (`feat`, `fix`, `style`, `docs`, `chore`, `test`) → `git push`.
3. One builder: a single agent builds the whole Fruit System. No subagents and no other AI models.
4. Never: commit, print or paste a key (`.env` is git-ignored; `.env.example` lists names only); put the Supabase
   service-role key anywhere except Netlify Function environment variables; put demo data in the client's deployment;
   tick `[x]` without evidence from your own run; force-push.
5. Ask the founder only for what MASTERPROMPT /goal lists: a real secret or account, a paid action, a change to price,
   legal terms or what the signed agreement promises, or "done". Everything else: decide, write it in `DECISIONS.md`,
   continue.
6. Before your session ends: push, and overwrite the `status.md` HANDOFF NOTE (2–4 lines).
