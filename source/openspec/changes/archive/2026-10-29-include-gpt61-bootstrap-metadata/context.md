# Verification

The bootstrap change supplies missing GPT-6.1 Sol metadata before the first
upstream refresh. The deployed image is `codex-lb:bootstrap-gpt61-c2a7bb60`,
built from source revision `c2a7bb600e051eefdc04d1a9e3646e0a569a6db1`.

Bootstrap metadata alone did not resolve Desktop's compaction loop. Desktop
subsequently set `api_key_model_discovery` to false through
`experimentalFeature/enablement/set`. Reproducing that setting against the
installed app-server returned an empty model list, despite an explicit
CodexLB `model_catalog_url`. The same process returned the live catalog when
discovery remained enabled.

The CodexLB launcher now preserves discovery for a local `codex-lb` provider
with an explicit catalog URL. The client has no `model_catalog_json`,
`model_context_window`, or `model_auto_compact_token_limit` override.

Live Desktop verification on 2026-10-29 recorded discovery enabled, an
828,400-token effective context window, and a 784,800-token default compaction
threshold. A resumed supervisor executed 14 commands and 12 MCP calls with
no compaction items. Post-sampling logs reported usage below the threshold
and `token_limit_reached=false`. Previously, the same Desktop runtime used a
258,400-token fallback window and compacted after each tool call.

The dashboard's saved 1,050,000-token override remains subject to the
catalog's current 872,000-token maximum. This change does not bypass that
maximum or claim to validate requests above it.

The change passed strict OpenSpec validation before archival. A subsequent
full-spec strict check reported 8 passing and 60 failing existing specs. The
main spec files are unchanged from the preceding commit; those broader
validation failures are not corrected by this catalog fix.
