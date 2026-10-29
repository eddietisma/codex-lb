## ADDED Requirements

### Requirement: Response connections advertise the scoped model catalog

Codex-native model catalog responses MUST include an `ETag` derived from their
serialized content. Backend HTTP Responses and both response WebSocket routes
MUST advertise the current caller-scoped catalog tag as `x-models-etag`.
Unchanged catalog content MUST produce the same tag; changed content MUST
produce a different tag. Computing the tag MUST NOT reserve catalog-request
quota or select an inference account.

#### Scenario: Client opens a response WebSocket

- **GIVEN** the caller can fetch a Codex-native catalog
- **WHEN** the caller opens a response WebSocket
- **THEN** its handshake advertises the same tag as the catalog

#### Scenario: Catalog content changes

- **GIVEN** a catalog has an entity tag
- **WHEN** its model metadata changes
- **THEN** subsequent catalog and response connections advertise the updated tag
