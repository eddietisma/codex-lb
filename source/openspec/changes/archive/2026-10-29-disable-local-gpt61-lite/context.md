# Verification

- Source revision: `6c7950110a616a630a222763cb9a1503757b659e`.
- Catalog integration suite: 63 passed, one existing Starlette deprecation warning.
  Ran from an isolated tracked-source copy because pytest could not scan the
  checkout's inaccessible `.claude` path.
- Ruff checks, Ruff formatting, and Git whitespace checks passed.
- OpenSpec strict change validation and all 68 specifications passed.
- Image: `codex-lb:catalog-no-lite-6c795011`.
- Running image digest:
  `sha256:79e85709a882e292105df5d41f03914b28c14073f9abfaa11643f93f2e0419be`.
- Both live Codex catalog routes report `use_responses_lite: false` for
  `gpt-6.1-sol`; GPT-6 Sol, GPT-6 Astra, and GPT-5.6 Sol retain `true`.
- A standard Responses request carrying a function tool completed with `OK`
  before and after deployment.
- The app liveness endpoint returned `status: ok`.
- Recreated only the application service. PostgreSQL and its data were retained.

The original failing Codex thread has not been retried with a refreshed catalog.
Its failure is not claimed resolved. Restart Codex to reload model metadata.
The source commit is unsigned because GPG signing waited for interactive input.
