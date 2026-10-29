# Local Lite opt-in

The operator requested Lite in the model configuration. The catalog response now
sets `use_responses_lite: true` for GPT-6.1 Sol instead of forcing it off. Other
models retain their advertised values, including GPT-6 Astra.

For example, `GET /backend-api/codex/models` returns a GPT-6.1 Sol entry with
`"use_responses_lite": true` without modifying the upstream model registry.

This is a catalog setting change, not a repair of Lite's unsupported-tool error.
Clients must refresh the catalog to observe it. Historical standard-request
normalization remains unchanged, and no tool declarations are rewritten or
discarded by this change.

## Verification

- Model catalog, request-serialization, and Lite parallel-call suites passed,
  332 tests in total. The changed catalog assertions failed against the previous
  false override before the implementation change.
- Ruff checks and formatting checks passed for both modified Python files.
- Strict validation passed for this OpenSpec change. Repository-wide strict
  spec validation reported 8 passing and 60 failing specs. The failing-spec
  list matches an isolated copy of unchanged HEAD, including existing long
  requirement warnings.
