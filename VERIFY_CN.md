# Local offline reproduction and import

Run from the current candidate root:

```sh
python3 tools/verify_candidate.py
```

After import, run from this evidence directory and pass the actual Content9 package:

```sh
python3 tools/verify_candidate.py --package /absolute/path/to/soul-content/move/soulidity_content
```

The script contains the pinned CLI default path and SHA256; `--cli` accepts only the same SHA256. It requires exactly nine source files and frozen Standard/Foundation sources, and parses the actual package manifest's two local dependency paths. Every round creates a fresh `evidence/verifier-runs/<time>-<id>/graph`, copying these actual inputs and frozen Sui, MoveStdlib, Walrus and WAL sources/tests/Published metadata; all graph manifests become local. It reads no RPC, signs nothing, touches no consumers and does not fetch packages over the network.

It first runs an independent production build, saves a new source/manifest freeze, local manifest diff, generated lock and compiler artifacts, and compares raw SHA/all module handles for the nine actual compiled modules. Address normalization replaces only values explicitly belonging to Content/Standard/Foundation/Walrus/WAL in the bytecode address table; all remaining bytes must equal. Address changes are not interpreted as old type compatibility. It then adds original storage12 + pure paging7 tests to the same isolated graph and runs 19 VM tests with the default gas budget. Logs, exact commands and actual counts go into a new `evidence.json`, without overwriting original round1 source9/149 functions/32 structs/common14 exports raw evidence.

Verified round: `evidence/verifier-runs/20261010-155100-b3e15ea4/evidence.json`, production exit0, 19/19 VM, nine modules equal after address-table normalization. Two earlier failures remain: round1 dump zeroed references to multiple unpublished packages, making address roles indistinguishable; round2 copier omitted upstream tests folders, missing walrus::test_utils, with actual test count 0. Round3 fixes only the reproducer and dependency copying; product sources, guards, abilities and original test assertions are unchanged.

At root integration, retain `tools/`, `offline-vendor/`, `frozen-original/`, initial `packages/` frozen dependencies and `evidence/`, then copy the nine sources and four test files from `packages/soulidity_content` to the actual candidate. The actual repository manifest may relocate local dependencies; do not import `packages/content_original` or the three excluded modules. After actual manifest relocation, use new rounds of this reproducer as evidence, preserving old evidence as the original isolated baseline. The reproduction graph does not replace full-journey acceptance for original Core, Native, authorization or paid access.
