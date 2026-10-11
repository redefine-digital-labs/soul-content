# soul-content

CONTENT: optional content and access protocol. Content references, custody renewal, access and recovery; Kind format and scope validation form a separate foundational unit.

This repository solely maintains the current nine content sources and three ContentKinds sources. The Kinds package contains actual Registry/AdminCap/events/initialization and scope/name/read validation; Cap write authority for the actual Registry ID remains, with no new permissionless registry factory.

[Current independent product CI](evidence/content-current-kinds/runs/1791647507025959000/summary.json) passes: independent Content9 production build, original 19 tests, and byte equality of nine modules with their integrated Content12 counterparts; 29 local inputs, 435 selected compiler caches and 9 controls are unchanged before and after. Original nine sources and four test bodies are preserved. Entry point tools/run_content_current.py uses staged actual-input replay; only pinned local locations and hashes are redirected, and the CLI does not write directly to actual source paths.

The three retained publication responsibilities in original Content12 still await extraction; independent on-chain publication, upgrades, autonomous governance and actual recovery journeys remain unaccepted. The previous pinned Content9 verifier, Core/Native artifact-equality proof and 40 input-guard checks remain historical and cannot be treated as a full artifact-equality claim after this round's changes.

Maintenance entry points: [MODULE](MODULE.md), [Agent boundaries](AGENTS.md), [compatibility](COMPATIBILITY.md), [operation and recovery](RUNBOOK.md), [machine configuration](module.json). Recommended role LUQI; original Owner unchanged. Unconfirmed actual maintenance and qualified acceptance mappings remain pending.

```sh
python3 scripts/ci.py
python3 scripts/ci.py --product
python3 scripts/ci.py --release-ready
```

Default CI checks only the maintenance contract; product commands execute registered current independent verification. Full release gates remain pending, and commands do not deploy or sign. Complete recovery must include this round's actual manifest/lock and ContentKinds dependencies; do not simply run the old pinned graph and claim current-product verification.

## Current checkpoint

See [construction status](CONSTRUCTION_STATUS.md) for current evidence, blockers, recovery material and remote coordination. This checkpoint is not a release.
