# CONTENT execution boundaries

- Read MODULE.md, COMPATIBILITY.md, RUNBOOK.md and module.json, then the original record and exact candidate; historical statuses are references only.
- The original Owner and record are the responsibility entry point. The recommended role LUQI is not an actual account; unconfirmed maintenance/acceptance mappings remain pending.
- Write this module only in this repository's authoritative worktree; do not modify other repositories incidentally through relative paths, symlinks, integration fixes or tool scripts. Hand cross-repository issues to the corresponding maintainer on the original record.
- Only one writer may work on each semantic unit at a time. Parallel work requires scope authorization, capacity within the original WIP, isolated write domains, pinned inputs, independent review capacity and no shared-resource conflicts.
- Do not treat maintenance/upgrade roles as wallet, asset, operation or deployment authority. Follow the original explicit authorization; documentation creates no new signing, spending or external-sending authority.
- The 10 contract fields are in module.json.agent_contract: identity, responsibilities, write_scope, inputs_outputs, tool_identity, permissions, budget, acceptor, handoff_location, stop_method.
- Attach stage, status, evidence, exit criteria and handbook applicability to the original Delivery/DEV/BUG; do not create another task board. Preserve original milestones and active Owners.
- High-risk work requires review by a qualified, independent actual acceptor; role labels and executor self-review must not masquerade as independent approval.
- Keep build/test at not_run when unexecuted; successful template CI does not establish business acceptance, independent release, deployment or external audit.

Dependency snapshots `.deps/` and `candidate-dependencies/` are read-only build inputs, never a second business source authority. Changes require an explicit new candidate and dependency pin; do not edit another repository through an old-path link.

Frozen external inputs packages/soulidity_standard, packages/soulidity_foundation, offline-vendor and frozen-original are read-only and outside this repository's maintenance scope. packages/soulidity_content is a relative-location link to this repository's move/soulidity_content; only one source/test copy exists.
