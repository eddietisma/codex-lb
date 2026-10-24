## Why

A resolved continuity owner is the only account allowed to serve an anchored request. Its transient error backoff currently empties that one-account pool and returns `continuity_owner_unavailable` even when the account remains active.

## What changes

Allow transient backoff fallback for a pool narrowed to a hard continuity owner. Keep persisted unavailability, quotas, cooldowns, and healthy sibling preference unchanged.

Adapted from Soju06/codex-lb PR #2486 at `bfc2efa2a5fc8cff63dc3bbc463a9e26a03c5dc3`, by cigro and Darafei Praliaskouski.

## Capabilities

### Modified capabilities

- `sticky-session-operations`: keep a resolved hard owner selectable during transient backoff.

## Impact

Account selection only. No database migration, setting, dependency, or transport replay changes.
