# Contributing locally

This is an independent repository. Do not import sibling repositories. Run `./verify.ps1 -MoonPath /absolute/path/to/moon` before committing. Add meaningful public-API regressions for behavior changes; do not add tests that only mirror low-impact implementation details. Once relevant checks pass, repeat them only after new changes or failures justify it. Document unsupported behavior and observable errors.

`moon fmt`, `moon info` and generated locale/golden sources must be idempotent. Rebuild `web/engine.mjs` from the actual library. Data changes must retain the Faker MIT license and pinned source hashes in `data/provenance.json`; use an external official reference directory following TESTING.md. Do not bundle the wheel or reference Python runtime into production.

Normal verification replays captured official outputs offline and exercises real CLI/Worker lifecycles. Independently captured results must not be replaced by local expected output. Record benchmark scope, adapters, runtime/CPU and limitations; do not treat a few faster tasks as full parity. Local validation does not imply remote CI, publication or final acceptance.
