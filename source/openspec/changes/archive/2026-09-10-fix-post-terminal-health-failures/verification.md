# Local verification

Adapted from Soju06/codex-lb PR #2319 at
`26cfb9e8b18b3391a78c46877fe7e6be85f25aed` by Yannic Charlon.

On 2026-10-24, all four stream-handler cases failed before implementation with
an escaped health-write exception or duplicate terminal. The public ASGI
`/v1/responses` regression also reproduced two terminals instead of one.
After the fix the public route passes, and all 75 selected stream health,
settlement, terminal, and owner-rewrite tests pass.

The adaptation preserves the local #2665 upstream HTTP status evidence. Only
ordinary exceptions in six post-terminal health writes are contained. Existing
settlement order and cancellation behavior remain in place. Focused lint,
formatting, typing, and strict specifications are checked before commit.
