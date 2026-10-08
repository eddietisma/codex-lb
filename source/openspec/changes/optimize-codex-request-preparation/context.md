# Closure investigation

Read-only investigation found 126 incomplete requests in the rolling 24-hour window: 97 masked native receive errors, 26 peer closes with code 1000 and three with code 1012. Native peer-close codes survive the Rust/Python adapter. The majority with no code were generic receive failures, so the earlier characterization of all failures as premature peer closes was too broad.

No worker, socket-reuse or recovery defect was confirmed as the cause. Log only an allowlisted native failure phase, with unknown values mapped to unknown. Keep the public error envelope, replay safety and account-health classification unchanged. These diagnostics support a later cause-specific correction; they do not establish a stream reliability improvement.

# Validation limitations

Four proxy-environment selection tests fail on this Windows environment with proxy None. They fail identically with the previous source at 2ca6a6c8. The other native transport tests, including the new sanitized diagnostics cases, pass. Native compact fixtures require PYTHONUTF8=1 on Windows.
