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

Source revision `7a5bc7f8218cbdde56555c9ace1b87ce86e3c221` was built and deployed
as `codex-lb:key-redirect-gui-7a5bc7f8`. Compose pins that tested revision.

The three GPT-6 rules are stored on the only existing key, `codex`, as:

```text
gpt-6-astra:gpt-6.1-sol,gpt-6-sol:gpt-6.1-sol,gpt-6-luna:gpt-6.1-sol
```

The global environment mapping was removed. The key's allowlist was
canonicalized to preserve the same effective access and visible model list:
`gpt-6.1-sol`, `gpt-reserve`, and `codex-auto-review`.

All three live source-model probes completed with OpenAI reporting
`gpt-6.1-sol`. Readiness reported database `ok`. The served edit-dialog bundle
contained the new syntax/example and helper copy. The PostgreSQL container
identity and start time were unchanged.

The previous key policy was saved outside the repository at
`E:/.tmp/codexlb-key-redirect-gui/before-policy.json`. To roll back to the prior
deployment, restore the saved key policy before starting its older image,
which does not understand conditional enforced model strings.
