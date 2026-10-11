# Consumed contracts and verification combinations

Register actual consumers and dependencies in module.json.compatibility; an empty list means gate 0 is incomplete and cannot establish zero dependencies.
Configuration declares eight fields per consumer, eight fields per dependency and seven dependency categories, which CI validates.
Fill in the provider's exact interface, actual actions/types, schema/behavior, required effects, authority/state, failure/exit/recovery, version/artifact and verification/migration evidence separately.

Check changes in four dimensions: types/formats/ABI, behavior, authority/funds, and migration/old entry points.
Verify at least baseline/current, candidate/current and candidate/candidate; add reverse combinations when reverse consumption exists.
Pin source, dependency locks, configuration and artifacts; reject floating latest and incorrect hashes. Reverification does not automatically require republication of unrelated consumers.
For unknown passive extensions, the target is 0 forced market publications; fulfill or explicitly reject funds/authorization/supply/transfer/content/exit obligations according to the actually selected contracts.

Register actual packages/SDK artifacts, type origins, exact dependencies and upgrade boundaries individually in release_units; shared UpgradeCaps must disclose the joint upgrade boundary.
Version numbers, directory separation or a compilable ABI do not prove funds/authorization/recovery compatibility.


## Current ContentKinds consumer combination

The independent Content9 manifest and lock declare current ContentKinds/Standard/Foundation; the original nine sources and four test files are unchanged. Each of the nine compiled modules equals the corresponding integrated Content12 bytes, and the original 19 tests pass. The 29 local inputs, 435 actual compiler caches and tools/controls are unchanged before and after. This proves only the selected unpublished combination, not old type identity, Registry governance, independent upgrades or complete recovery.

The canonical sources of ContentKinds Registry/Cap/events change, so relevant Consumers must consume the new target origins; this adaptation cannot substitute for zero forced market republications for passive extensions. The old pinned Content9 graph and historical consumer artifact-equality evidence remain in historical; module.json.ci defines this round's product command and exact configuration.
