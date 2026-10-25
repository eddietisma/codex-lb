The affected Pro 200 account's first matching baseline was recorded at 2026-10-24 12:04:42.528168 UTC. Its integer `blocked_at` was 2026-10-24 12:04:42 UTC. The resolver selected that fractional-second sample, but validation truncated it to the blocked second and rejected it. Later matching samples and a confirmed weekly 100% to 0% reset were present.

The fix preserves same-second rows for deadline ambiguity detection and selects a later baseline using validation's existing whole-second fence. It does not weaken the fence or accept available quota without a matching reset transition.

Validation: the integration regression failed on the original implementation. The scheduler, recovery, updater, reset-credit, and probe suites pass. Ruff and strict validation of this OpenSpec change pass. Repository-wide strict OpenSpec validation reports existing warnings across 60 specifications, including long requirements and missing scenarios; unrelated specifications were not edited.

A direct request on the affected account completed successfully with HTTP 200 before deployment, confirming that OpenAI accepted the account while CodexLB still blocked it.
