# CONTENT maintenance contract

Nature: optional content and access protocol. Authoritative state: content/Blob lifecycles, access policies and in-domain authorization.
Semantic maintenance units: references and custody, access authorization, content recovery.

Only this repository is writable; gate 0 pins exact original source, type origins, function ABI, release units, all UpgradeCaps and consumers in module.json.
An empty release_units means exact package/artifact boundaries are incomplete; repository counts cannot be treated as counts of independent upgrades or deployments.
[]

Record management functions planning/organizing/leading/controlling, management-tool capabilities and engineering capabilities separately.
Verify four authority categories individually: source maintenance, version release, production deployment and on-chain control; prove upgrade, asset-control and operational authority separately.

Advance work through the original record; stage, status, evidence and exit criteria are separate fields.
Eight stages: Plan → Code → Build → Test → Release → Deploy → Operate → Monitor; stage=null in a new template means the original record's current stage has not yet been reviewed.
Record applicable handbook v1.0 sections, evidence and remaining checks on the original Delivery/DEV/BUG; original scope links and Owners come from the original registry. Do not copy historical statuses into current status.

Cutover: save baseline → pin target authoritative candidate → independent verification → pin consumer versions → combination verification → stop dual writing by ending writes at the old location.
Before cutover, the template is not another issuance authority; verify source cutover separately from on-chain writer/issuer cutover.


## Current source and verification

The repository's 12 sole implementation sources are original Content9 and ContentKinds3; the latter contains actual Registry/AdminCap/events/initialization. The Kinds compiler closure is Soul-free, but actual Registry administration still requires proof of third-party self-custody and recovery paths. Content9 storage still consumes current Standard/Foundation; Kind's pure-format nature does not establish that all Content is free from authority dependencies.

Current independent CI is tools/run_content_current.py: staged replay of 29 installed inputs, 435 selected caches and 9 controls preserved, original 19 tests pass, and nine modules byte-equal the current integrated Content12 subset. Code/Build/Test pass only for this increment; three retained publication responsibilities, actual package/upgrade boundaries, on-chain operation and all recovery journeys remain pending. Earlier fixed-body verification is separately historical. Original Owner, three maintenance units and incomplete release_units status remain.
