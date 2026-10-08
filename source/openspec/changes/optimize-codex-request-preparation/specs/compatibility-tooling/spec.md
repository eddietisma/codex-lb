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
