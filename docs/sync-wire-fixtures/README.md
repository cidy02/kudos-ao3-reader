# D5 sync wire byte vectors

Run `python3 docs/sync-wire-fixtures/checker/check.py` from the repository root. Each JSON file contains a fixed hexadecimal object, its SHA-256, and a short scenario note. The checker parses all eleven objects, verifies canonical JSON in the fixture's ASCII/integer JCS subset, checks envelope and blob hashes, verifies Ed25519 bootstrap, segment and authority signatures, reconstructs every object byte for byte, asserts the gap and equivocation identities, and rejects two tampered signed objects. It uses only Python's standard library.

`--write` regenerates the fixed vectors and is for intentional format changes only. The checker currently checks *wire structure*, not D4 reducer projection or complete checkpoint semantics. The checkpoint vector has empty retained summaries because their schema remains pending D4. The opaque vector preserves an unknown noncritical record with `minReaderMinor=1`; it does not assert future semantic meaning. A valid `asset.write` blob reference can be applied before the blob vector arrives.

Fixtures deliberately use ASCII JSON, integer timestamps and small payloads. Production JCS, Unicode normalization and large streaming limits need separate iOS/Android conformance tests before D7.
