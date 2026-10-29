# naim-local: one database for every local client system

The local clients' systems (Hotel, Duka, Water, Fruit) keep their records in one Supabase project of their own,
**naim-local**, never in the company's office project. The office project holds Naim's own leads, clients and
agreements; a stall's sales and debts never sit beside them, and a problem or a restore in one never touches the other.

Status (29 October 2026): the framework is written and proven on a local Postgres; the project itself does not exist
yet. Creating a Supabase project is the founder's step (this session may not create one), and so is the plan.

## How it keeps clients apart

| Piece | What it does |
|---|---|
| One schema per system | `hotel`, `duka`, `water`, `fruit`. One copy of each system's tables and migrations serves all its clients. |
| One `business_id` per client | Every table has it; `naim.tenants` lists the clients (system, slug, agreement number, plan, plan state). |
| Who is asking | The sign-in token's `app_metadata`: `business_id` and `app_role` (owner, seller, attendant, cashier, delivery, assistant_owner, assistant_staff). Only our Netlify Functions can set app_metadata; a user cannot change it. |
| `naim.protect(schema, table)` | Row-level security on every table: read and write only your own business; writer roles only; delete by the owner only; append-only tables refuse updates and deletes; `readers` limits a table to some roles (costs and profit for the owner). A table nobody protected is closed. |
| Late payment | `plan_state = read_only` (day 30 in the agreements) stops every write through `naim.can_write()`; reading and the export keep working, so data is never withheld. |
| `<system>.my_plan` | The signed-in business's plan and state, for the app's banner. |
| The assistants | Each client's Hermes profiles sign in as that business's own `assistant_owner` / `assistant_staff` users, so the same rules hold for them (docs/HERMES-ISOLATION.md). |

Proof, run on Postgres 16 with a stand-in for Supabase's `auth.jwt()`:
`psql "$LOCAL_PG" -v ON_ERROR_STOP=1 -f supabase/naim-local/tests/framework_test.sql` → 12 checks, `ALL PASS`: own
business only; no writing into, changing or moving rows to another business; sellers cannot delete or read costs;
the owner's assistant reads what the owner reads; append-only holds; unprotected tables are closed; read-only keeps
every record readable and stops writes; a token without a business, a malformed business id and anonymous visitors
see nothing; only migrations can run the builders. The framework runs twice without harm.

**Why one schema per system and not per client:** one migration per system instead of one per client, one set of
exposed schemas, and the same proven policies everywhere. A client can still be lifted out whole at any time (their
own project, or the hand-back when they leave): every row carries their `business_id`.

## Founder steps (once)

1. **Create the project** in the Supabase dashboard: organization *Naim Automation Systems CO.*, name `naim-local`,
   region `eu-west-1` (the same as the office project), a long database password kept in your password manager.
2. **SQL editor:** paste and run `supabase/naim-local/001_framework.sql`.
3. **Settings → API → Exposed schemas:** add each system's schema when its build arrives (`hotel`, `duka`, `water`,
   `fruit`). Leave `naim` unexposed.
4. **Keys:** each client app's Netlify site gets the project URL and the publishable key (browser-safe). The
   service-role key goes **only** into that site's Netlify Function environment variables, pasted by you in the
   Netlify dashboard; never in chat, never in a repo, never on the VPS.
5. **Backups** (the free plan keeps none): on the VPS, `apt install postgresql-client-17 age rclone`; on your own PC,
   `age-keygen -o naim-backup-key.txt` and keep that file offline; put only its public key (`age1…`) and the database
   connection string in `/etc/naim/naim-local-backup.env` (mode 600); add the cron line from the top of
   `ops/backup/naim-local-backup.sh`. Every night it dumps the framework and the system schemas, plus the sign-in
   accounts, encrypts them to your key (the server can write them but never read them), keeps 30 days and copies
   them off the VPS if `RCLONE_REMOTE` is set. Tested locally: an encrypted-only rule (it refuses to keep a plain
   dump), an unreachable database and a pg_dump older than the server all stop it with a clear message.

## Plan and size (Supabase pricing, checked 29 October 2026)

| | Free (today's plan) | Pro |
|---|---|---|
| Projects | 2 active: the office and naim-local fill both | each extra project adds its compute (Micro $10 a month) |
| Database | 500 MB per project | 8 GB disk per project, then $0.125 per GB |
| Inactivity | paused after 1 week | never paused |
| Backups | none (our nightly dumps above) | daily, kept 7 days (our dumps stay as a second copy) |
| Price | $0 | from $25 a month, including $10 of compute (one Micro) |

A busy stall writes about 2,200 rows a day (sales, lines, stock moves, payments, the audit log), roughly 300 MB a
year at most, so the free 500 MB holds about two busy clients for a year. **Recommendation:** build and test on Free;
move the organization to Pro before the first client goes live, because a paused or unbacked database is not
acceptable for a live business. That is the founder's call (a paid action).

## Restore (a lost or broken project)

1. Decrypt on your PC: `age -d -i naim-backup-key.txt naim-local-<stamp>.dump.age > naim-local.dump` (the same for
   the `naim-local-auth-<stamp>` file).
2. Create a new project, then `pg_restore --no-owner -d "<new connection string>" naim-local.dump`. Schemas,
   tables, rows, policies and grants come back together (tested on a fresh database: the restored copy enforced
   row-level security straight away).
3. Sign-in accounts: `pg_restore --data-only -d "<new connection string>" naim-local-auth.dump`.
4. Exposed schemas (step 3 above), then each client app's URL and keys in Netlify.

## A client leaving (the 90-day hand-back)

Export their records from their app (JSON and CSV), hand them over, then delete every row with their
`business_id` from their system's tables, their `naim.tenants` row, their sign-in accounts and their stored files,
and record it in the support log. Their Hermes user is removed as in docs/HERMES-ISOLATION.md.

## For each system's builder

The system's first migration runs `select naim.add_system('<system>');`, creates its tables (each with
`business_id uuid not null default <system>.current_business()`), and calls `select naim.protect('<system>',
'<table>' …);` for every table, with `append_only => true` for ledgers, stock moves and events and `readers =>
array['owner','assistant_owner']` for costs, margins and profit. Onboarding a client (a Netlify Function with the
service role) inserts their `naim.tenants` row and creates their people and assistant users with `app_metadata`
`{business_id, app_role}`.

## Sources

- Supabase pricing and plan limits: https://supabase.com/pricing
- The company's Supabase organization and project (Free plan; project `igoczmpxnpgahslejlhi`, eu-west-1, Postgres
  17), read through the Supabase connector on 29 October 2026.
