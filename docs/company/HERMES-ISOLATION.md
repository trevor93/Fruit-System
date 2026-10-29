# Hermes per client: the wall between clients

Every local client gets its own assistant (the Nourish Agent, Msaidizi wa AdibayoWaters, Msaidizi wa Matunda …). They
all live on the company's Contabo VPS, so one rule decides the design: **no client's assistant can ever see, use or
slow down another client's**. This page is the company standard; the Water and Fruit master prompts (section 9.1) and
`ops/hermes/` follow it.

## What Hermes itself says (checked 29 October 2026)

| Fact | Source |
|---|---|
| "Profiles do **not** sandbox the agent." On the local backend the agent has the same filesystem access as the Linux account it runs as. | Profiles guide |
| Each profile is its own Hermes home: its own `config.yaml`, `.env`, `SOUL.md`, memories, sessions, skills, cron jobs and state database. Never point two agent processes at one profile. | Profiles guide |
| "For production gateway deployments, use `docker`, `modal`, `daytona`, or `vercel_sandbox` backend to isolate agent commands from your host system." "For maximum security, run the gateway on a separate machine or VM." "Never run the gateway as root." | Security guide |
| Podman works as the container engine: set `HERMES_DOCKER_BINARY=podman`. Container keys: `docker_volumes`, `docker_network` (`false` = no network), `container_cpu`, `container_memory` (MB), `container_persistent`, `lifetime_seconds`; `terminal.home_mode: profile` keeps tool subprocesses off the real `HOME`. `agent.disabled_toolsets` removes toolsets everywhere. | Configuration guide |
| The API server (`API_SERVER_ENABLED`, `API_SERVER_PORT` default 8642, `API_SERVER_HOST` default `127.0.0.1`, `API_SERVER_KEY`) gives **full access to the agent's toolset, including terminal commands**; the key is "required for every deployment". `/health` is public; `/v1/toolsets` (keyed) lists what the agent can use. Each profile can run its own API server on its own port with its own key. | API server guide |

So profiles separate a client's *settings*, not its *reach*. The wall has to come from the operating system.

## The standard: four walls for every client

1. **Its own Linux user.** `hermes-<slug>`, home `/srv/hermes/<slug>` (mode 700), created by
   `ops/hermes/new-client.sh <slug>`. Hermes runs as that user and never as root. No client user can read another's
   home, secrets, memory or workspace; `ops/hermes/check-isolation.sh <a> <b>` proves it line by line.
2. **Only its own tools.** A client system's assistant needs its MCP server (`water-mcp`, `fruit-mcp` …) and memory.
   Everything else is off with `agent.disabled_toolsets` (terminal, file, code execution, browser, web: confirm the
   exact names with `hermes tools list` on the server, then write them in the client's `config.yaml`). Gate: `GET
   /v1/toolsets` shows nothing else, and "run ls /" fails. If a client ever needs a terminal (none does today), it runs
   in that user's rootless Podman (`terminal.backend: docker`, `HERMES_DOCKER_BINARY=podman`), seeing only
   `docker_volumes: [/srv/hermes/<slug>/workspace:/workspace]`, with `docker_network: false` unless it truly needs the
   internet: that is the `terminal-isolation.yaml` the script writes.
3. **Only its own data.** The MCP server signs in to Supabase as the client's own assistant Auth user
   (`assistant-owner` / `assistant-staff`, with `app_metadata.business_id` and `app_role`), using the publishable key.
   Row-level security limits it to that business and that role. The service-role key never touches the VPS.
4. **One front door, one key.** Each profile's API server has its own port and its own long random
   `API_SERVER_KEY`, listens on the loopback only, and Caddy (TLS) is the only public way in:
   `https://agents.<domain>/<slug>/owner/*` and `/<slug>/staff/*`. Only the client app's Netlify Function holds the
   keys (`HERMES_OWNER_KEY`, `HERMES_STAFF_KEY`); browsers never call Hermes, so `API_SERVER_CORS_ORIGINS` stays empty.

Plus **limits**: the script caps the user's systemd slice (`MemoryMax`, `CPUQuota`, `TasksMax`), so one busy client
cannot slow the others down.

## Two ways to run a client's Hermes (same four walls)

| | A. Native, as the client user | B. In the client user's rootless container |
|---|---|---|
| How | `sudo -iu hermes-<slug>` → `hermes setup` → `hermes gateway install` (Hermes writes its own user service) | the system repo's `agent/docker/compose.client.yaml`, run with rootless Podman **as `hermes-<slug>`** (the official image supervises each profile's gateway itself) |
| Profiles | `owner` and `staff` in that user's `~/.hermes` | the same two, on the container's volume |
| Ports | `API_SERVER_HOST=127.0.0.1`, ports from the table below | inside: `API_SERVER_HOST=0.0.0.0` on 8642/8643; published **only** as `127.0.0.1:<port>` from the table below |
| Use it for | pilots and the first clients | the client systems once their repo ships the compose file (Water, Fruit) |

Container hardening for B: non-root user inside, read-only root filesystem except the profile volume, `--cap-drop ALL`,
`--security-opt no-new-privileges`, a memory limit (start at 1 GB; measure and record), `--pids-limit 256`, no Docker or
Podman socket mounted, restart unless stopped.

Ports: a loopback port is reachable by any process on the VPS, so the key is what guards it, and no client assistant
has a terminal to try. Each client gets its own pair, worked out from its Linux user id so two clients can never clash:
**owner `20000 + 2 × (uid mod 1000)`, staff the next one**. `new-client.sh` prints the pair.

## New client, step by step (as root on the VPS)

1. `ops/hermes/new-client.sh --dry-run <slug>`, read it, then `ops/hermes/new-client.sh <slug> 2G 100`.
2. Note the owner and staff ports it prints.
3. As the client user: `hermes profile create owner` and `hermes profile create staff`, then `hermes -p owner setup`
   and `hermes -p staff setup` (the 9router base URL and this client's own 9router key; the Telegram bot token for the
   owner profile only).
4. In each profile's `.env`: `API_SERVER_ENABLED=true`, its port, a new `API_SERVER_KEY` (`openssl rand -hex 32`), and
   the Supabase URL, publishable key and that profile's assistant user. Nothing else.
5. In each profile's `config.yaml`: the MCP server, `agent.disabled_toolsets`, voice (`tts.provider: edge`,
   `sw-KE-ZuriNeural`), `terminal.home_mode: profile`.
6. `hermes -p owner gateway install` and `hermes -p staff gateway install` (services `hermes-gateway-owner` and
   `hermes-gateway-staff` for this user), then start both.
7. Caddy: add the two routes; reload.
8. Netlify (the client app's site): `HERMES_BASE_URL`, `HERMES_OWNER_KEY`, `HERMES_STAFF_KEY`.
9. Proof, recorded in the system repo's `status.md`: `curl https://agents.<domain>/<slug>/owner/health` → ok;
   `/v1/toolsets` with the key → only the allowed toolsets; "run ls /" → refused; `ops/hermes/check-isolation.sh <slug>
   <another-client>` → `RESULT: isolated`; the staff assistant user reads no costs (RLS test).
10. Back up `/srv/hermes/<slug>/.hermes` nightly with the client's database rows (encrypted, off the VPS, 30 days).

## Leaving

On the 90-day ending: stop and disable both gateways, remove the Caddy routes, delete the Netlify keys, archive the
export for the client, then `userdel -r hermes-<slug>`, delete its backups, and record it in the support log.

## Sources

- Profiles: https://hermes-agent.nousresearch.com/docs/user-guide/profiles
- Security: https://hermes-agent.nousresearch.com/docs/user-guide/security
- Configuration (terminal backends, Podman, toolsets): https://hermes-agent.nousresearch.com/docs/user-guide/configuration
- API server: https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server
