## ADDED Requirements

### Requirement: Conditional API key model policies across routes

HTTP Responses, WebSocket Responses, compaction, chat completions, and source
forwarding MUST use the same conditional API key model policy. The target model
MUST reach authorization, upstream routing and usage accounting. Unmapped models
MUST retain existing behavior. Conditional rules MUST NOT restrict a model
catalog to a single forced target or expose raw rule strings as model names.
Reasoning effort, service tier and other API key restrictions MUST remain
effective.

#### Scenario: Conditional rule across request paths

- **GIVEN** a key redirects `gpt-6-sol:gpt-6.1-sol`
- **WHEN** a supported proxy route receives a GPT-6 Sol request
- **THEN** the upstream request and accounting use `gpt-6.1-sol`
- **AND** catalogs never publish `gpt-6-sol:gpt-6.1-sol` as a model identifier
