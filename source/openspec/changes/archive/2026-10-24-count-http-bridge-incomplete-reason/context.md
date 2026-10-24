# Local adaptation

Adapted from Soju06/codex-lb PR #2278 at
`93d12ba97983e5d6a80d4c72b152c53021fb9727` by Yannic Charlon.

Local verification on 2026-10-24 reproduced two missing-strike failures before
implementation. All nineteen reader cases pass afterward, covering raw and
interpreted terminals, explicit-error precedence, neutral or unknown reasons,
duplicates, and attempt exclusions. The classifier uses the existing reason
reader and retry recorder. It does not change downstream payloads or account
health treatment. Focused Ruff lint/format and typing pass.

Six existing public HTTP bridge integration cases also pass, covering both Responses routes, connection reuse, persistent streaming, and valid failure SSE. Strict OpenSpec validation passed all 68 main specifications.
