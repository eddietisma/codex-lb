## ADDED Requirements

### Requirement: Local standard GPT-6.1 Sol requests omit historical Lite bundles

When a `gpt-6.1-sol` request explicitly supplies top-level `tools`, the local
proxy MUST omit `additional_tools` input items from its upstream serialization.
It MUST preserve current tool declarations and other history items without
mutating the original request. Historical bundles alone MUST NOT enable Lite for
these standard requests. Requests without explicit top-level tools and other
models MUST retain their existing behavior.

#### Scenario: Existing thread switches from Lite to standard tools

- **GIVEN** a GPT-6.1 Sol request contains historical `additional_tools` and explicit top-level tools
- **WHEN** the proxy serializes the upstream request
- **THEN** it omits the historical tool bundle and retains current tools
- **AND** it does not synthesize a Lite marker from the omitted bundle

#### Scenario: An existing Lite client omits standard tools

- **GIVEN** a GPT-6.1 Sol request includes `additional_tools` and omits top-level tools
- **WHEN** the proxy serializes the upstream request
- **THEN** the Lite bundle remains unchanged
