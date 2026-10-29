## ADDED Requirements

### Requirement: Full-history WebSocket recovery attempts are correlatable

When an anchored WebSocket request installs a retained full-history body for recovery, the service SHALL emit one `websocket_full_history_replay` warning marked `stage=prepared`. It SHALL include the request id, hashed conversation/session/previous-response/owner identifiers, input-item count, and replay state. The event SHALL NOT contain input text, credentials, or raw continuity identifiers. Ordinary incremental continuations SHALL NOT emit this event.

#### Scenario: Quota recovery emits a bounded diagnostic

- **GIVEN** an unavailable owner requires safe recovery through a retained original body
- **WHEN** the proxy removes its inserted anchor and prepares the full-history body
- **THEN** one warning identifies the recovery request and its hashed conversation
- **AND** the preparation event does not claim that upstream dispatch or completion succeeded

#### Scenario: Subsequent incremental messages do not repeat recovery warnings

- **GIVEN** full-history recovery succeeded on a replacement account
- **WHEN** later messages continue from that account's responses
- **THEN** those messages emit no full-history replay warning

#### Scenario: Rejected recovery does not claim full-history preparation

- **GIVEN** account-owned or incomplete context prevents installing a fresh body
- **WHEN** the request retains its required owner
- **THEN** no full-history replay warning is emitted
