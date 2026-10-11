/// Stable scope bits shared by descriptors, Soul authorization and content.
module soulidity_content::permissions;
public fun scope_seal():u64{1}
public fun scope_memory():u64{2}
public fun scope_skills():u64{4}
public fun scope_assets():u64{8}
