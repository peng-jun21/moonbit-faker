# Validation contract

- Explicit Wasm-GC and JS targets: no inference from the toolchain default.
- Public API tests plus compiled browser engine, CLI stdin/file/argument and failure exit-code checks.
- 307 seeded bounded malformed inputs including UTF-16 surrogates. The worker has a 20-second limit.
- Local code coverage: `moon coverage analyze -p localreview/faker -- -f summary`. No coverage upload is configured. Coverage is evidence about current code, not upstream feature coverage.
- Benchmark: 5 warmups and 30 measured documented-example executions; median and p95 recorded locally.
- Generated API and browser artifact must match the same source revision.

CI files are prepared locally; remote CI has not run because this repository has not been uploaded. Compatibility beyond README scope remains unverified.

## 0.3 actual validation

- 16 JS tests passed, including unchanged profile golden seeds. The 8 new provider tests also passed on Wasm-GC; old Wasm-GC tests were not repeated this stage.
- GS1's published body/check-digit vector 629104150021 -> 6291041500213 passes. Deterministic replay, sampling, zero weights, Gregorian century rules, exact decimal strings, uniqueness failure and CSV escaping are covered.
- `node tools/test-records.mjs` generated 256 rows x 26 columns in JSON/JSONL/CSV, exercised all 25 provider variants, rejected 10 malformed configurations, and checked the actual schema-file and empty-JSONL CLI paths. Original CLI checks also passed.
- `python3 tools/validate-records.py` ran under WSL using standard uuid, ipaddress, datetime, decimal, csv, json, urllib.parse and re modules plus the GS1 modulo-10 invariant. All 256 records and three format equivalences passed. Raw generated files and their SHA-256 values are retained in evidence.
- `node tools/benchmark-records.mjs`: one cold local Node.js v24.11.0 / Windows x64 measurement generated/rendered 10,000 x 6 values in 215 ms, 1,555,382 UTF-8 bytes. This is a single sample including request processing, not a general throughput or memory guarantee.
- No Python Faker distribution/locale/seed parity run, allocation-registry validation, new full fuzz/coverage suite, global workspace checks, archive rebuild, remote CI or upload was performed. Old evidence retains its original date and scope.
