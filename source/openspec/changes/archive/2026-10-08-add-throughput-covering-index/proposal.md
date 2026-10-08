# Add throughput covering index

The throughput chart scans request-log heap pages because the existing usage index lacks plan type and latency. Add a separate partial index containing every throughput column. Preserve all sample and grouping rules.
