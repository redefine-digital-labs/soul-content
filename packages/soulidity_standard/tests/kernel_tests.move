#[test_only]
module soulidity_standard::kernel_tests;
use std::bcs;
use std::hash;
use std::string;
use std::type_name;
use sui::test_scenario::{Self, Scenario};
use soulidity_standard::soul::{Self, Soul};
use soulidity_standard::foreign;

public struct Witness has drop {}
public struct SoulProducer has drop {}
public struct OtherWitness has drop {}
public struct Source has key, store { id: UID }
public struct Value has key, store { id: UID, score: u64 }
fun h(): vector<u8> { vector::tabulate!(32, |_| 9) }
fun source(ctx: &mut TxContext): Source { Source { id: object::new(ctx) } }
fun value(score: u64, ctx: &mut TxContext): Value { Value { id: object::new(ctx), score } }
fun create(ctx: &mut TxContext): Soul {
    let p = source(ctx);
    let s = soul::new(SoulProducer {}, &p, 1, h(), string::utf8(b"test"), ctx);
    transfer::public_transfer(p, ctx.sender()); s
}
fun install(s: &mut Soul, permanent: bool, schema: u16, ctx: &mut TxContext): ID {
    let v = value(7, ctx); let id = object::id(&v);
    let expected = soul::revision(s);
    soul::install(s, Witness {}, b"ability", v, schema, !permanent, h(), expected); id
}
fun finish(s: Soul, mut sc: Scenario) { transfer::public_transfer(s, sc.ctx().sender()); sc.end(); }

#[test]
fun provenance_is_real_object_and_actual_producer_type() {
    let mut sc = test_scenario::begin(@0xa); let p = source(sc.ctx()); let id = object::id(&p);
    let s = soul::new(SoulProducer {}, &p, 3, h(), string::utf8(b"OC"), sc.ctx());
    let o = soul::origin(&s);
    assert!(soul::source(&o) == id && soul::minted_by(&o) == @0xa && soul::source_version(&o) == 3, 0);
    assert!(soul::producer(&o) == type_name::with_defining_ids<SoulProducer>() && soul::source_type(&o) == type_name::with_defining_ids<Source>(), 1);
    transfer::public_transfer(p, @0xa); finish(s, sc)
}
#[test]
fun install_update_and_exit_keep_object_identity_and_commitment() {
    let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx());
    let id = install(&mut s, false, 1, sc.ctx());
    let before = soul::manifest_hash(&s);
    let d = soul::descriptor<Witness>(&s, b"ability").destroy_some();
    assert!(soul::module_id(&d) == id && soul::body_hash(&d) == hash::sha3_256(bcs::to_bytes(soul::borrow_module<Witness, Value>(&s, b"ability"))), 0);
    let (mut v, ticket) = soul::begin_update<Witness, Value>(&mut s, Witness {}, b"ability", 1);
    v.score = 19; soul::commit_update(&mut s, ticket, Witness {}, v, 2, h());
    assert!(soul::revision(&s) == 2 && soul::manifest_hash(&s) != before, 1);
    assert!(soul::borrow_module<Witness, Value>(&s, b"ability").score == 19, 2);
    let v = soul::uninstall<Witness, Value>(&mut s, b"ability", 2);
    assert!(object::id(&v) == id && v.score == 19 && soul::module_count(&s) == 0, 3);
    transfer::public_transfer(v, @0xa); finish(s, sc)
}
#[test]
fun permanent_module_updates_without_becoming_removable() {
    let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); let id = install(&mut s, true, 1, sc.ctx());
    let (mut v, ticket) = soul::begin_update<Witness, Value>(&mut s, Witness {}, b"ability", 1);
    v.score = 8; soul::commit_update(&mut s, ticket, Witness {}, v, 1, h());
    let d = soul::descriptor<Witness>(&s, b"ability").destroy_some();
    assert!(!soul::removable(&d) && soul::module_id(&d) == id, 0); finish(s, sc)
}
#[test]
fun same_label_in_distinct_typed_namespaces_is_isolated() {
    let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 1, sc.ctx());
    soul::install(&mut s, OtherWitness {}, b"ability", value(21, sc.ctx()), 1, true, h(), 1);
    assert!(soul::module_count(&s) == 2 && soul::borrow_module<Witness, Value>(&s, b"ability").score == 7 && soul::borrow_module<OtherWitness, Value>(&s, b"ability").score == 21, 0);
    assert!(soul::module_page(&s, 1, 1).length() == 1 && soul::module_page(&s, 2, 64).is_empty(), 1); finish(s, sc)
}
#[test]
fun transfer_whole_root_keeps_child_and_source_for_buyer() {
    let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); let id = install(&mut s, false, 1, sc.ctx());
    let root = object::id(&s); let hash = soul::manifest_hash(&s); transfer::public_transfer(s, @0xb);
    sc.next_tx(@0xb); let mut s: Soul = sc.take_from_sender();
    assert!(object::id(&s) == root, 0); soul::assert_manifest(&s, 1, hash);
    let v = soul::uninstall<Witness, Value>(&mut s, b"ability", 1); assert!(object::id(&v) == id, 1);
    transfer::public_transfer(v, @0xb); sc.return_to_sender(s); sc.end();
}
#[test, expected_failure(abort_code=3, location=soulidity_standard::soul)]
fun primitive_cannot_attest_production() { let mut sc = test_scenario::begin(@0xa); let p = source(sc.ctx()); let s = soul::new(true, &p, 1, h(), string::utf8(b"bad"), sc.ctx()); transfer::public_transfer(p, @0xa); finish(s, sc) }
#[test, expected_failure(abort_code=3, location=soulidity_standard::soul)]
fun producer_cannot_claim_another_module_source() { let mut sc = test_scenario::begin(@0xa); let p = foreign::new(sc.ctx()); let s = soul::new(SoulProducer {}, &p, 1, h(), string::utf8(b"bad"), sc.ctx()); transfer::public_transfer(p, @0xa); finish(s, sc) }
#[test, expected_failure(abort_code=3, location=soulidity_standard::soul)]
fun witness_cannot_install_another_module_value() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); soul::install(&mut s, Witness {}, b"ability", foreign::new(sc.ctx()), 1, true, h(), 0); finish(s, sc) }
#[test, expected_failure(abort_code=1, location=soulidity_standard::soul)]
fun stale_revision_rejected() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 1, sc.ctx()); soul::install(&mut s, Witness {}, b"other", value(1, sc.ctx()), 1, true, h(), 0); finish(s, sc) }
#[test, expected_failure(abort_code=6, location=soulidity_standard::soul)]
fun duplicate_namespace_and_name_rejected() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 1, sc.ctx()); install(&mut s, false, 1, sc.ctx()); finish(s, sc) }
#[test, expected_failure(abort_code=8, location=soulidity_standard::soul)]
fun permanent_child_cannot_be_withdrawn() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, true, 1, sc.ctx()); let v = soul::uninstall<Witness, Value>(&mut s, b"ability", 1); transfer::public_transfer(v, @0xa); finish(s, sc) }
#[test, expected_failure(abort_code=4, location=soulidity_standard::soul)]
fun wrong_value_type_rejected() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 1, sc.ctx()); let _ = soul::borrow_module<Witness, Source>(&s, b"ability"); finish(s, sc) }
#[test, expected_failure(abort_code=4, location=soulidity_standard::soul)]
fun wrong_namespace_rejected() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 1, sc.ctx()); let _ = soul::borrow_module<OtherWitness, Value>(&s, b"ability"); finish(s, sc) }
#[test, expected_failure(abort_code=2, location=soulidity_standard::soul)]
fun manifest_cannot_certify_temporarily_absent_child() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 1, sc.ctx()); let (v, ticket) = soul::begin_update<Witness, Value>(&mut s, Witness {}, b"ability", 1); let _ = soul::manifest_hash(&s); soul::commit_update(&mut s, ticket, Witness {}, v, 1, h()); finish(s, sc) }
#[test, expected_failure(abort_code=2, location=soulidity_standard::soul)]
fun edits_block_other_root_mutations() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 1, sc.ctx()); let (v, ticket) = soul::begin_update<Witness, Value>(&mut s, Witness {}, b"ability", 1); soul::install(&mut s, Witness {}, b"other", value(1, sc.ctx()), 1, true, h(), 1); soul::commit_update(&mut s, ticket, Witness {}, v, 1, h()); finish(s, sc) }
#[test, expected_failure(abort_code=9, location=soulidity_standard::soul)]
fun edit_cannot_replace_original_object_with_new_id() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 1, sc.ctx()); let (v, ticket) = soul::begin_update<Witness, Value>(&mut s, Witness {}, b"ability", 1); transfer::public_transfer(v, @0xa); soul::commit_update(&mut s, ticket, Witness {}, value(2, sc.ctx()), 1, h()); finish(s, sc) }
#[test, expected_failure(abort_code=9, location=soulidity_standard::soul)]
fun edit_cannot_commit_to_another_soul() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); let mut other = create(sc.ctx()); install(&mut s, false, 1, sc.ctx()); let (v, ticket) = soul::begin_update<Witness, Value>(&mut s, Witness {}, b"ability", 1); soul::commit_update(&mut other, ticket, Witness {}, v, 1, h()); transfer::public_transfer(s, @0xa); finish(other, sc) }
#[test, expected_failure(abort_code=10, location=soulidity_standard::soul)]
fun schema_cannot_regress() { let mut sc = test_scenario::begin(@0xa); let mut s = create(sc.ctx()); install(&mut s, false, 2, sc.ctx()); let (v, ticket) = soul::begin_update<Witness, Value>(&mut s, Witness {}, b"ability", 1); soul::commit_update(&mut s, ticket, Witness {}, v, 1, h()); finish(s, sc) }
#[test, expected_failure(abort_code=5, location=soulidity_standard::soul)]
fun paging_cannot_use_overflowing_or_unbounded_range() { let mut sc = test_scenario::begin(@0xa); let s = create(sc.ctx()); let _ = soul::module_page(&s, 18446744073709551615, 64); finish(s, sc) }

#[test]
fun nested_souls_keep_distinct_identity_origin_and_original_id_exit() {
    let mut sc = test_scenario::begin(@0xa); let mut parent = create(sc.ctx()); let mut child = create(sc.ctx());
    let parent_id = object::id(&parent); let child_id = object::id(&child);
    let parent_source = soul::source(&soul::origin(&parent)); let child_source = soul::source(&soul::origin(&child));
    let item = install(&mut child, true, 1, sc.ctx()); let child_hash = soul::manifest_hash(&child);
    soul::nest(&mut parent, child, 0);
    let d = soul::descriptor<soul::NestedSoulWitness>(&parent, bcs::to_bytes(&child_id)).destroy_some();
    assert!(soul::module_id(&d) == child_id && soul::semantic_hash(&d) == child_hash && soul::removable(&d), 0);
    assert!(object::id(&parent) == parent_id && parent_id != child_id && parent_source != child_source, 1);
    let child = soul::unnest(&mut parent, child_id, 1);
    assert!(object::id(&child) == child_id && soul::source(&soul::origin(&child)) == child_source, 2);
    assert!(soul::module_id(&soul::descriptor<Witness>(&child, b"ability").destroy_some()) == item, 3);
    transfer::public_transfer(child, @0xa); finish(parent, sc)
}

#[test]
fun nested_evolution_updates_parent_commitment_without_minting_another_identity() {
    let mut sc = test_scenario::begin(@0xa); let mut parent = create(sc.ctx()); let mut child = create(sc.ctx());
    let child_id = object::id(&child); let original = soul::origin(&child); let component_id = install(&mut child, true, 1, sc.ctx());
    soul::nest(&mut parent, child, 0); let before = soul::manifest_hash(&parent);
    let (mut child, nesting) = soul::begin_nested_update(&mut parent, child_id, 1);
    let (mut v, update) = soul::begin_update<Witness, Value>(&mut child, Witness {}, b"ability", 1);
    v.score = 12; soul::commit_update(&mut child, update, Witness {}, v, 1, h());
    let after_child = soul::manifest_hash(&child); soul::commit_nested_update(&mut parent, nesting, child);
    assert!(soul::manifest_hash(&parent) != before && soul::revision(&parent) == 2, 0);
    let child = soul::nested(&parent, child_id);
    assert!(object::id(child) == child_id && soul::origin(child) == original && soul::revision(child) == 2, 1);
    let d = soul::descriptor<soul::NestedSoulWitness>(&parent, bcs::to_bytes(&child_id)).destroy_some();
    assert!(soul::semantic_hash(&d) == after_child && soul::module_id(&soul::descriptor<Witness>(child, b"ability").destroy_some()) == component_id, 2);
    finish(parent, sc)
}

#[test]
fun three_levels_transfer_together_and_exit_in_original_order() {
    let mut sc = test_scenario::begin(@0xa); let mut root = create(sc.ctx()); let mut child = create(sc.ctx()); let grandchild = create(sc.ctx());
    let root_id = object::id(&root); let child_id = object::id(&child); let grandchild_id = object::id(&grandchild);
    soul::nest(&mut child, grandchild, 0); soul::nest(&mut root, child, 0); transfer::public_transfer(root, @0xb);
    sc.next_tx(@0xb); let mut root: Soul = sc.take_from_sender();
    assert!(object::id(&root) == root_id && object::id(soul::nested(soul::nested(&root, child_id), grandchild_id)) == grandchild_id, 0);
    let mut child = soul::unnest(&mut root, child_id, 1); let grandchild = soul::unnest(&mut child, grandchild_id, 1);
    assert!(object::id(&child) == child_id && object::id(&grandchild) == grandchild_id, 1);
    transfer::public_transfer(child, @0xb); transfer::public_transfer(grandchild, @0xb); finish(root, sc)
}

#[test, expected_failure(abort_code=9, location=soulidity_standard::soul)]
fun nested_update_cannot_substitute_new_soul_for_original_child() {
    let mut sc = test_scenario::begin(@0xa); let mut root = create(sc.ctx()); let child = create(sc.ctx()); let child_id = object::id(&child);
    soul::nest(&mut root, child, 0); let (child, ticket) = soul::begin_nested_update(&mut root, child_id, 1);
    transfer::public_transfer(child, @0xa); soul::commit_nested_update(&mut root, ticket, create(sc.ctx())); finish(root, sc)
}

#[test, expected_failure(abort_code=9, location=soulidity_standard::soul)]
fun nested_update_cannot_restore_into_another_parent() {
    let mut sc = test_scenario::begin(@0xa); let mut root = create(sc.ctx()); let mut other = create(sc.ctx()); let child = create(sc.ctx()); let child_id = object::id(&child);
    soul::nest(&mut root, child, 0); let (child, ticket) = soul::begin_nested_update(&mut root, child_id, 1);
    soul::commit_nested_update(&mut other, ticket, child); transfer::public_transfer(root, @0xa); finish(other, sc)
}
