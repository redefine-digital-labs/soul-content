/// Stable scope delegates to the sole ContentKinds owner.
module soulidity_content::permissions;
use soulidity_content_kinds::content_permissions as canonical;
public fun scope_seal():u64{ canonical::scope_seal() }
public fun scope_memory():u64{ canonical::scope_memory() }
public fun scope_skills():u64{ canonical::scope_skills() }
public fun scope_assets():u64{ canonical::scope_assets() }
