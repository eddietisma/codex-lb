## ADDED Requirements

### Requirement: Request preparation optimization parity

Request preparation optimizations SHALL preserve forwarded JSON values, API-key usage budgets and fresh-replay eligibility. Slimming SHALL NOT mutate caller-owned input. Compaction SHALL preserve tool-pair selection, required indices, omission-marker contents and the final wire budget, including duplicate call IDs across tool protocols.

#### Scenario: Opaque context retains its conservative usage budget
- **WHEN** a request references an existing response or conversation
- **THEN** its input usage estimate remains unknown without serializing the complete request

#### Scenario: Unsafe fallback is not prepared
- **WHEN** a full resend contains an unmatched tool output
- **THEN** fresh replay remains unavailable and its unused fallback body is not serialized

#### Scenario: Oversized history is slimmed without mutation
- **WHEN** historical tool output or an inline image is replaced
- **THEN** the original caller-owned input remains unchanged

#### Scenario: Long compaction history retains the same selection
- **WHEN** compaction reconciles tool pairs and fits the wire budget
- **THEN** optimized matching and size accounting select the same indices and omission markers as the previous algorithm

### Requirement: Sanitized native receive diagnostics

Native WebSocket receive failures SHALL log an allowlisted failure category without raw exception details. Unknown categories SHALL be logged as unknown. Logging SHALL NOT change peer close codes, public error envelopes, replay eligibility or account-health classification.

#### Scenario: Native failure contains an unrecognized phase
- **WHEN** a native receive exception has an unrecognized phase string
- **THEN** the operator log records unknown without exposing the string

#### Scenario: Peer sends a close frame
- **WHEN** an upstream peer closes its socket
- **THEN** the existing close code is preserved and no native receive-failure warning is emitted
