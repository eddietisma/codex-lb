## Upstream provenance

The imported upstream base `f8ffbac2099a113fba54dfd8d77774f5bca80ffa` and upstream main `72630bbfeee9e3b0d9acfb95e2b1e706b8b0188e`, fetched on 2026-10-29, both omit the pre-connect retained-body fallback and require proxy-injected anchors for owner-switch replay. The original unavailable-owner blockage therefore predates the local source changes.

Local revision `c617610a` added the missing reconnect fallback but also broadened quota replay to client-supplied anchors. That broadening was a local mistake. The inherited full-resend classifier accepts structurally self-contained input with an unknown previous response, even if those messages omit earlier context. The new route counterexample reproduced an incorrect successful account switch for two partial messages before the correction.

## Corrected boundary

Quota recovery may release only an anchor the proxy itself inserted into a retained, originally unanchored body. Client-supplied response identifiers retain their owner. The original request must still pass the existing account-neutral classifier. Account-scoped files, encrypted reasoning, compaction state, explicit turn-state ownership, and incomplete tool history do not gain account-switch authority.

This is fresh-request recovery, not migration of the old upstream session. Only the replayable request body is sent to the replacement account; account-owned server state is not transferred. The local chat and checkout are not moved by the load balancer.

## Validation

- Two native-route counterexamples failed before the correction and pass afterward, preserving the original account for unknown client anchors.
- The focused quota-owner suite passed all 14 cases, including an actual prior turn and reconnect, a real-selector recovery, and encrypted reasoning and compaction rejection.
- The broader WebSocket, generate, sticky-routing, and quota-owner run passed 222 tests. The same unrelated HTTP goal-restart scope test remains excluded after its unchanged-base timeout was established in the preceding change.
- All 351 selector and soft-sticky unit tests passed.
- Targeted Ruff, formatting, type checks, and strict OpenSpec change validation passed.

## Deployment

The running local service uses `codex-lb:quota-owner-9d91136d`, built from source revision `9d91136dcb37d30122e73a5463399f17d35b3824`. The packaged production modules matched the source SHA-256 hashes before rollout. The normal shutdown drain completed and `/health/ready` returned `status: ok` with `database: ok`.

The code provenance audit establishes where the missing recovery path existed. It does not prove that this path alone caused the original chat incident: the captured logs also included selections with no preferred owner and no selected account, and affinity was manually changed before an end-to-end incident replay was captured.
