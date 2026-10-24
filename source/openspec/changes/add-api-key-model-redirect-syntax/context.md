# Validation

- 243 focused backend parser, service and request-policy tests passed.
- 80 route/API cases passed for deployment redirects and key-scoped rules,
  including HTTP, WebSocket, compaction, chat, bridge, catalogs and isolation.
- Nine existing enforcement/catalog regression cases passed.
- 48 frontend tests passed; final key-table tests also passed after layout QA.
- Backend Ruff/Ty and frontend typecheck, scoped ESLint and Vite build passed.
- Strict OpenSpec change validation passed.
- Desktop and mobile screenshots were inspected after dialog animations settled.
  Captures are in `E:/.tmp/codexlb-key-redirect-ui/`.

An additional related unit slice passed 110 cases. Four unchanged warmup
fixtures failed before production code on Windows `datetime.fromtimestamp`
calls for negative timestamps. No unrelated fixture edits were made.

# Deployment

The existing deployment environment maps the three GPT-6 names globally. The
new deployment will store those exact rules on the only existing key, `codex`,
and remove the global environment mapping. Its allowlist will be canonicalized
to preserve the same effective model access and visible model list.

Source and deployment changes remain separate commits. The Compose source pin
must identify the tested application revision.
