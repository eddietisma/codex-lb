## ADDED Requirements

### Requirement: Exhausted WebSocket owners recover through verified fresh history

When a previous-response owner has exhausted quota, native Responses WebSocket selection and pre-visible quota rejection SHALL use a retained verified account-neutral full-history body to retry normal account selection. The fresh body SHALL retain the complete verified input and omit the previous response identifier. A client-supplied anchor MAY be released only when the existing full-resend classifier verifies the retained fresh body.

#### Scenario: Exhausted owner fails before an upstream connection opens

- **GIVEN** a request has a previous-response owner with exhausted quota
- **AND** the proxy retained a verified account-neutral full-history body
- **AND** another eligible account has quota
- **WHEN** reconnect selection cannot select the previous-response owner
- **THEN** the proxy retries selection without the previous response identifier
- **AND** the replacement account receives the full-history body
- **AND** the client receives a successful response without an intermediate quota error

#### Scenario: Owner rejects a verified full resend before output

- **GIVEN** a client-supplied previous response has a verified account-neutral full-history resend
- **AND** its owner rejects the request with quota exhaustion before a response becomes visible
- **WHEN** another eligible account has quota
- **THEN** the proxy retries the full history on the replacement account within the existing replay limit

#### Scenario: Replacement pool is exhausted

- **GIVEN** a verified fresh replay cannot find an eligible replacement account
- **WHEN** normal account selection reports exhausted quota
- **THEN** recovery terminates through the existing selection failure path

### Requirement: Quota recovery preserves ownership and request limits

Fresh quota replay SHALL preserve explicit turn-state ownership, file ownership, raw legacy ownership, API-key account assignments, security requirements, request budgets, attempt bounds, and reservation lifecycles. The proxy SHALL NOT move delta-only continuations or retained bodies that are not account-neutral.

#### Scenario: Account-owned or incomplete context stays on its owner

- **GIVEN** a request has only delta history, an account-scoped file, or explicit turn-state ownership
- **WHEN** its required owner exhausts quota
- **THEN** the proxy preserves the required ownership
- **AND** it does not send the request to another account
