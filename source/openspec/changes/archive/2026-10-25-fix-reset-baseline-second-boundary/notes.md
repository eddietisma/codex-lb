The affected Pro 200 account's first matching baseline was recorded at 2026-10-24 12:04:42.528168 UTC. Its integer `blocked_at` was 2026-10-24 12:04:42 UTC. The resolver selected that fractional-second sample, but validation truncated it to the blocked second and rejected it. Later matching samples and a confirmed weekly 100% to 0% reset were present.

The fix preserves same-second rows for deadline ambiguity detection and selects a later baseline using validation's existing whole-second fence. It does not weaken the fence or accept available quota without a matching reset transition.

Validation: the integration regression failed on the original implementation. All 241 tests in the scheduler, recovery, updater, reset-credit, and probe suites pass. Ruff and strict validation of this OpenSpec change pass. All 68 specifications pass normal OpenSpec validation. Repository-wide strict validation reports existing warnings across 60 specifications, including long requirements and missing scenarios.

A direct request on the affected account completed successfully with HTTP 200 before deployment, confirming that OpenAI accepted the account while CodexLB still blocked it.

Deployed source revision `04260918176463c47b9b9ab24c76c0f24b43c2ec` as `codex-lb:reset-baseline-04260918`, pinned separately in deployment commit `ec9b6c2a`. Readiness returned `status=ok` with `database=ok`.

After startup, the ordinary background scheduler changed the affected Pro 200 account from `rate_limited` to `active` and cleared both block markers. No manual status write or reset-credit redemption was used. The other exhausted Pro 200 account remained blocked.

A temporary API key scoped only to the recovered account verified the full proxy path. The request returned HTTP 200 and `response.completed`; persisted request `resp_0c22ffe6f9c32390016ade3b3729f48191ad1f030811b3fe64` records that account, `status=success`, 17 input tokens, and 5 output tokens. The temporary key was deleted in the verification script's `finally` block.
