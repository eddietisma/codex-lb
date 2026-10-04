## ADDED Requirements

### Requirement: Model transitions publish child turn-state tokens

HTTP bridge responses MUST allocate a fresh downstream turn-state token before sending response headers when the incoming API-key-scoped durable turn-state belongs to an incompatible model. An account-neutral transition fork MUST register this token against the child session. The parent token MUST retain its original session and account ownership. Compatible-model requests and unknown incoming tokens MUST retain existing token behavior. Owner-forwarded requests MUST preserve the token assigned by the originating instance.

#### Scenario: Follow-up after an account-neutral model transition

- **GIVEN** a durable parent session and a model transition that requires an account-neutral child fork
- **WHEN** the client sends the next turn using the returned token
- **THEN** the bridge resolves the child session and reuses its upstream connection
- **AND** the parent token still resolves to the original parent session
