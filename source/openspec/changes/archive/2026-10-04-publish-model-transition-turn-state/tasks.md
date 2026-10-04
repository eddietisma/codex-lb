## Implementation

- [x] Allocate model-transition response tokens before streaming headers.
- [x] Verify durable two-turn child reuse and preserved parent ownership.
- [x] Verify compatible-model reuse and equivalent HTTP response routes.
- [x] Run affected tests, static checks and strict OpenSpec validation. 1,267 affected cases and 168 ownership/API/chat cases pass. The existing idle-recovery timeout also reproduces on unchanged main and is excluded from the affected run.
