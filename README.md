# Codex LB

Private Docker Compose deployment with the locally patched application under `source/`.

The initial source snapshot is upstream https://github.com/Soju06/codex-lb at `f8ffbac2099a113fba54dfd8d77774f5bca80ffa`, plus the local changes through `53ae0fbbec20fe5e10d93f6f811d41342b6863c2`.

Local fixes preserve developer context and prewarm replay safety, recognize the Business Pro Lite plan identifier, parse multiline upstream WebSocket errors correctly, and normalize Responses-Lite parallel tool calls. The dashboard displays the internal `prolite` tier as `Pro 200` without changing its quotas or routing.

The upstream license and attribution files are retained in `source/`. The previous local clone remains under ignored `codex-lb/` for access to its original Git history. Edit `source/` for future changes.

## Run locally

Copy `.env.example` to `.env`, set a strong PostgreSQL password, then run:

```powershell
docker compose up -d --build --force-recreate
```

For an existing deployment with PostgreSQL already running, rebuild and restart only the app:

```powershell
docker compose up -d --build --force-recreate --no-deps codex-lb
```

Existing `.data/` and `.data-postgres/` bind mounts are preserved. This repository contains no credentials, encryption keys, databases, backups, or runtime captures. Supply those locally. A fresh clone starts with fresh local data unless existing runtime data is supplied separately.