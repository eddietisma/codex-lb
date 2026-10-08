# Closure investigation

Read-only investigation found 126 incomplete requests in the rolling 24-hour window: 97 masked native receive errors, 26 peer closes with code 1000 and three with code 1012. Native peer-close codes survive the Rust/Python adapter. The majority with no code were generic receive failures, so the earlier characterization of all failures as premature peer closes was too broad.

No worker, socket-reuse or recovery defect was confirmed as the cause. Log only an allowlisted native failure phase, with unknown values mapped to unknown. Keep the public error envelope, replay safety and account-health classification unchanged. These diagnostics support a later cause-specific correction; they do not establish a stream reliability improvement.

# Validation limitations

Four proxy-environment selection tests fail on this Windows environment with proxy None. They fail identically with the previous source at 2ca6a6c8. The other native transport tests, including the new sanitized diagnostics cases, pass. Native compact fixtures require PYTHONUTF8=1 on Windows.

# Synthetic measurements

On the same Windows host and deterministic 8,000-pair history, reconciliation improved from 1,201.25 ms to 13.80 ms with exactly the same selected indices. The complete lossless compaction path improved from 429.44 ms to 99.15 ms with equal resulting JSON values. These are different operations and their savings must not be added.

For sparse selection with 4,000 history items and 1,000 selected, incremental wire fitting improved from 714.85 ms to 202.62 ms; with 16,000 history items and 1,000 selected, 1,942.35 ms to 1,109.71 ms. Pair reconciliation still scans the history after each removal, which limits that path's gain.

On a synthetic 2.33 MB nested history, lazy-copy slimming improved from 34.872 ms to 1.155 ms; traced peak allocation dropped from 5,802,169 to 49,521 bytes. Original and optimized output values matched. Live first-token improvements have not been measured.
