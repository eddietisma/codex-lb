## MODIFIED Requirements

### Requirement: Exhausted WebSocket owners recover through verified fresh history

When a previous-response owner has exhausted quota, native WebSocket selection MAY release a proxy-injected anchor and retry normal selection with the retained original account-neutral request. The body SHALL retain its original input. Quota recovery MUST NOT release a client-supplied anchor merely because its input passes a structural full-resend classifier.

#### Scenario: Exhausted owner fails before an upstream connection opens

- **GIVEN** the client sent a complete request without a previous response identifier
- **AND** the proxy retained that original account-neutral body before inserting an anchor
- **WHEN** the inserted anchor's owner cannot serve the request because its quota is exhausted
- **THEN** the proxy may retry the retained original body on another eligible account
- **AND** the client receives no intermediate quota failure

#### Scenario: Owner rejects a verified full resend before output

- **GIVEN** the proxy inserted a previous response identifier into an originally unanchored request
- **AND** the proxy retained the original account-neutral body
- **WHEN** its owner rejects the request with quota exhaustion before a response becomes visible
- **THEN** the proxy may replay that original body on another eligible account within the existing replay limit

#### Scenario: Unknown client anchor has structurally self-contained partial history

- **GIVEN** the client supplied a previous response identifier
- **AND** its input contains multiple messages but omits earlier context
- **WHEN** the previous-response owner exhausts quota
- **THEN** the request remains owner-bound
- **AND** the proxy does not treat the partial input as proof of complete history

#### Scenario: Replacement pool is exhausted

- **GIVEN** a safe retained original body cannot find an eligible replacement account
- **WHEN** normal account selection reports exhausted quota
- **THEN** recovery terminates through the existing selection failure path
