# Verification

The affected thread's most recent saved replacement history contained an
`additional_tools` bundle. Codex's refreshed cache and the live catalog both
reported `use_responses_lite: false`, but the thread still received Lite errors.

A minimal live request with historical `additional_tools` and a current
`web_search` tool reproduced the exact upstream rejection. Removing the
historical bundle from that request produced `response.completed`.

## Checks

- 249 request unit tests passed.
- Six selected WebSocket integration cases passed, including byte-preserved
  current tools, retained Lite behavior, and historical-bundle conversion.
- Ruff lint, Ruff formatting, and Git whitespace checks passed.
- Strict change validation and all 68 OpenSpec specifications passed.
- After deployment, a live WebSocket request with the historical bundle,
  standard web search, and a stale Lite marker completed with `OK`.
- Catalog still reports Lite disabled for GPT-6.1 Sol; liveness returned `ok`.
- Original thread retry remains an operator check.

## Deployment

- Source revision: `079fa993e1ee8aff965643ec4e21b21ff2779de0`.
- Image: `codex-lb:standard-history-079fa993`.
- Running image digest:
  `sha256:12394c7699ee1ccd09fc2dfe61d061f4386b50ea456ff60ec541aaab5b491756`.
- Recreated only the application service. No PostgreSQL or data changes.
- Commits are unsigned because interactive GPG signing was unavailable.
