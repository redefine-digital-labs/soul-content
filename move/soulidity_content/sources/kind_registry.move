/// Delegates to the sole unpublished ContentKinds registry owner.
module soulidity_content::kind_registry;
use std::string::String;
use soulidity_content_kinds::content_kind_registry::{Self as canonical,KindDescriptor,KindRegistry,KindAdminCap,KindRegistryCreated,KindRegistered,KindDeprecated,KindReactivated};
public fun kind_soul_doc(): u32 { canonical::kind_soul_doc() }
public fun kind_memory(): u32 { canonical::kind_memory() }
public fun kind_skill(): u32 { canonical::kind_skill() }
public fun kind_sprite(): u32 { canonical::kind_sprite() }
public fun kind_audio(): u32 { canonical::kind_audio() }
public fun first_custom_kind(): u32 { canonical::first_custom_kind() }
public fun op_append(): u64 { canonical::op_append() }
public fun op_delete(): u64 { canonical::op_delete() }
public fun op_purge(): u64 { canonical::op_purge() }
public fun op_active_bind(): u64 { canonical::op_active_bind() }
public fun read_owner(): u64 { canonical::read_owner() }
public fun read_grant(): u64 { canonical::read_grant() }
public fun read_paid(): u64 { canonical::read_paid() }
public fun read_public(): u64 { canonical::read_public() }
public fun descriptor_kind(d: &KindDescriptor): u32 { canonical::descriptor_kind(d) }
public fun protocol_version(): u64 { canonical::protocol_version() }
public fun descriptor_version(d: &KindDescriptor): u64 { canonical::descriptor_version(d) }
public fun descriptor_name(d: &KindDescriptor): &String { canonical::descriptor_name(d) }
public fun descriptor_op_mask(d: &KindDescriptor): u64 { canonical::descriptor_op_mask(d) }
public fun descriptor_read_mode_mask(d: &KindDescriptor): u64 { canonical::descriptor_read_mode_mask(d) }
public fun descriptor_has_active_binding(d: &KindDescriptor): bool { canonical::descriptor_has_active_binding(d) }
public fun descriptor_requires_download_policy(d: &KindDescriptor): bool { canonical::descriptor_requires_download_policy(d) }
public fun descriptor_default_grant_scope_mask(d: &KindDescriptor): u64 { canonical::descriptor_default_grant_scope_mask(d) }
public fun descriptor_deprecated(d: &KindDescriptor): bool { canonical::descriptor_deprecated(d) }
public fun registry_id(self: &KindRegistry): ID { canonical::registry_id(self) }
public fun registry_version(self: &KindRegistry): u64 { canonical::registry_version(self) }
public fun next_kind(self: &KindRegistry): u32 { canonical::next_kind(self) }
public fun contains_kind(self: &KindRegistry, kind: u32): bool { canonical::contains_kind(self,kind) }
public fun contains_name(self: &KindRegistry, name: String): bool { canonical::contains_name(self,name) }
public fun borrow_descriptor(self: &KindRegistry, kind: u32): &KindDescriptor { canonical::borrow_descriptor(self,kind) }
public fun kind_for_name(self: &KindRegistry, name: String): u32 { canonical::kind_for_name(self,name) }
public fun register_kind(
    registry: &mut KindRegistry,
    cap: &mut KindAdminCap,
    name: String,
    op_mask: u64,
    read_mode_mask: u64,
    has_active_binding: bool,
    requires_download_policy: bool,
    default_grant_scope_mask: u64,
    _ctx: &mut TxContext,
): u32 { canonical::register_kind(registry,cap,name,op_mask,read_mode_mask,has_active_binding,requires_download_policy,default_grant_scope_mask,_ctx) }
public fun deprecate_kind(
    registry: &mut KindRegistry,
    cap: &mut KindAdminCap,
    kind: u32,
    _ctx: &TxContext,
) { canonical::deprecate_kind(registry,cap,kind,_ctx) }
public fun reactivate_kind(
    registry: &mut KindRegistry,
    cap: &mut KindAdminCap,
    kind: u32,
    _ctx: &TxContext,
) { canonical::reactivate_kind(registry,cap,kind,_ctx) }
public fun assert_kind_active(registry: &KindRegistry, kind: u32) { canonical::assert_kind_active(registry,kind) }
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { canonical::init_for_testing(ctx) }
#[test_only]
public fun destroy_admin_cap_for_testing(cap: KindAdminCap) { canonical::destroy_admin_cap_for_testing(cap) }
