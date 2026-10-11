/// Application-independent asset root. No mutable UID or mutable-child escape.
module soulidity_standard::soul;

use std::bcs;
use std::hash;
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::dynamic_object_field as dof;
use sui::event;

const ERevision: u64 = 1;
const EEditing: u64 = 2;
const EAuthority: u64 = 3;
const EType: u64 = 4;
const EInput: u64 = 5;
const EDuplicate: u64 = 6;
const ECapacity: u64 = 7;
const EPermanent: u64 = 8;
const EIdentity: u64 = 9;
const ESchema: u64 = 10;
const MAX_MODULES: u64 = 64;
const MAX_CHILD_BYTES: u64 = 245760;

/// Package ownership proof for standard Sui integrations such as a real
/// TransferPolicy<Soul>. The kernel does not install rules or depend on a market.
public struct SOUL has drop {}
fun init(w: SOUL, ctx: &mut TxContext) { sui::package::claim_and_keep(w, ctx) }
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(SOUL {}, ctx) }

public struct Soul has key, store {
    id: UID,
    schema: u16,
    name: String,
    revision: u64,
    origin: Origin,
    modules: vector<Descriptor>,
    editing: bool,
}

/// Source identity is an actual object input. Version/hash are its module's
/// attestation, not a kernel interpretation of a Maker or a storage service.
public struct Origin has copy, drop, store {
    producer: TypeName,
    source_type: TypeName,
    source: ID,
    source_version: u64,
    source_hash: vector<u8>,
    minted_by: address,
}

public struct Descriptor has copy, drop, store {
    namespace: TypeName,
    name: vector<u8>,
    value_type: TypeName,
    object: ID,
    schema: u16,
    removable: bool,
    body_hash: vector<u8>,
    semantic_hash: vector<u8>,
}

/// Private constructor and typed DOF keys isolate every application namespace.
public struct ModuleKey<phantom W> has copy, drop, store { name: vector<u8> }

/// Canonical native nesting namespace. A nested Soul remains a distinct asset,
/// never a new form of its parent. Constructor stays inside this module.
public struct NestedSoulWitness has drop {}

/// No abilities: successful transactions must restore this exact child into
/// this exact Soul. Permanent modules can be edited but cannot be withdrawn.
public struct Edit<phantom W, phantom T> {
    soul: ID,
    object: ID,
    name: vector<u8>,
    revision: u64,
}

public struct Changed has copy, drop {
    soul: ID, revision: u64, operation: u8,
    namespace: TypeName, name: vector<u8>, object: ID,
}

public struct Manifest has copy, drop, store {
    domain: vector<u8>, soul: ID, schema: u16, name: String,
    revision: u64, origin: Origin, modules: vector<Descriptor>,
}

fun same_module<W, T>() {
    let w = type_name::with_original_ids<W>();
    let t = type_name::with_original_ids<T>();
    assert!(!w.is_primitive() && !t.is_primitive(), EAuthority);
    assert!(w.address_string() == t.address_string()
        && w.module_string() == t.module_string(), EAuthority);
}

fun hash32(value: &vector<u8>) { assert!(value.length() == 32, EInput) }
fun check_name(value: &vector<u8>) {
    assert!(value.length() > 0 && value.length() <= 64, EInput)
}
fun ready(s: &Soul) { assert!(s.schema == 1 && !s.editing, EEditing) }
fun cas(s: &Soul, expected: u64) { assert!(s.revision == expected, ERevision) }
// Root contents use Sui's execution-level Move object size bound. Imposing a
// smaller name/root ceiling here changes the original native metadata domain.
fun child_hash<T>(value: &T): vector<u8> {
    let bytes = bcs::to_bytes(value);
    assert!(bytes.length() <= MAX_CHILD_BYTES, ECapacity);
    hash::sha3_256(bytes)
}

public fun new<W: drop, P: key>(
    witness: W, source: &P, source_version: u64,
    source_hash: vector<u8>, name: String, ctx: &mut TxContext,
): Soul {
    same_module<W, P>(); let _ = witness;
    // Same-module public metadata values also have drop. Only the producer's
    // designated marker may attest issuance; its constructor must remain private.
    assert!(*type_name::with_original_ids<W>().datatype_string().as_bytes()==b"SoulProducer",EAuthority);
    hash32(&source_hash);
    assert!(source_version > 0, EInput);
    let s = Soul {
        id: object::new(ctx), schema: 1, name, revision: 0, modules: vector[], editing: false,
        origin: Origin {
            producer: type_name::with_defining_ids<W>(),
            source_type: type_name::with_defining_ids<P>(), source: object::id(source),
            source_version, source_hash, minted_by: ctx.sender(),
        },
    };
    s
}

fun find<W>(s: &Soul, name: &vector<u8>): Option<u64> {
    let namespace = type_name::with_defining_ids<W>();
    let mut i = 0;
    while (i < s.modules.length()) {
        if (s.modules[i].namespace == namespace && s.modules[i].name == *name)
            return option::some(i);
        i = i + 1
    };
    option::none()
}

fun index<W, T>(s: &Soul, name: &vector<u8>): u64 {
    let found = find<W>(s, name);
    assert!(found.is_some(), EType);
    let i = found.destroy_some();
    assert!(s.modules[i].value_type == type_name::with_defining_ids<T>(), EType);
    i
}

fun changed(s: &mut Soul, operation: u8, d: &Descriptor) {
    s.revision = s.revision + 1;
    event::emit(Changed {
        soul: object::id(s), revision: s.revision, operation,
        namespace: d.namespace, name: d.name, object: d.object,
    })
}

public fun install<W: drop, T: key + store>(
    s: &mut Soul, witness: W, name: vector<u8>, value: T,
    schema: u16, removable: bool, semantic_hash: vector<u8>, expected: u64,
) {
    ready(s); cas(s, expected); same_module<W, T>(); let _ = witness;
    check_name(&name); hash32(&semantic_hash); assert!(schema > 0, ESchema);
    assert!(find<W>(s, &name).is_none(), EDuplicate);
    assert!(s.modules.length() < MAX_MODULES, ECapacity);
    let d = Descriptor {
        namespace: type_name::with_defining_ids<W>(), name,
        value_type: type_name::with_defining_ids<T>(), object: object::id(&value),
        schema, removable, body_hash: child_hash(&value), semantic_hash,
    };
    dof::add(&mut s.id, ModuleKey<W> { name }, value);
    s.modules.push_back(d); changed(s, 0, &d)
}

public fun borrow_module<W, T: key + store>(s: &Soul, name: vector<u8>): &T {
    ready(s); let _ = index<W, T>(s, &name);
    dof::borrow(&s.id, ModuleKey<W> { name })
}

public fun uninstall<W, T: key + store>(s: &mut Soul, name: vector<u8>, expected: u64): T {
    ready(s); cas(s, expected);
    let i = index<W, T>(s, &name); let d = s.modules[i];
    assert!(d.removable, EPermanent);
    let value = dof::remove<ModuleKey<W>, T>(&mut s.id, ModuleKey<W> { name });
    assert!(object::id(&value) == d.object, EIdentity);
    s.modules.remove(i); changed(s, 1, &d); value
}

public fun begin_update<W: drop, T: key + store>(
    s: &mut Soul, witness: W, name: vector<u8>, expected: u64,
): (T, Edit<W, T>) {
    ready(s); cas(s, expected); same_module<W, T>(); let _ = witness;
    let i = index<W, T>(s, &name); let id = s.modules[i].object;
    let value = dof::remove<ModuleKey<W>, T>(&mut s.id, ModuleKey<W> { name });
    assert!(object::id(&value) == id, EIdentity);
    s.editing = true;
    (value, Edit { soul: object::id(s), object: id, name, revision: expected })
}

public fun commit_update<W: drop, T: key + store>(
    s: &mut Soul, ticket: Edit<W, T>, witness: W, value: T,
    schema: u16, semantic_hash: vector<u8>,
) {
    same_module<W, T>(); let _ = witness; hash32(&semantic_hash);
    let Edit { soul, object: id, name, revision } = ticket;
    assert!(s.editing && soul == object::id(s) && id == object::id(&value), EIdentity);
    cas(s, revision);
    let i = index<W, T>(s, &name);
    let mut d = s.modules[i];
    assert!(d.object == id, EIdentity); assert!(schema >= d.schema, ESchema);
    d.schema = schema; d.body_hash = child_hash(&value); d.semantic_hash = semantic_hash;
    dof::add(&mut s.id, ModuleKey<W> { name }, value);
    *s.modules.borrow_mut(i) = d; s.editing = false; changed(s, 2, &d)
}

public fun revision(s: &Soul): u64 { s.revision }
public fun schema(s: &Soul): u16 { s.schema }
public fun name(s: &Soul): &String { &s.name }
public fun origin(s: &Soul): Origin { s.origin }
public fun source(o: &Origin): ID { o.source }
public fun source_type(o: &Origin): TypeName { o.source_type }
public fun producer(o: &Origin): TypeName { o.producer }
public fun source_version(o: &Origin): u64 { o.source_version }
public fun source_hash(o: &Origin): vector<u8> { o.source_hash }
public fun minted_by(o: &Origin): address { o.minted_by }
public fun module_count(s: &Soul): u64 { ready(s); s.modules.length() }
public fun descriptor<W>(s: &Soul, name: vector<u8>): Option<Descriptor> {
    ready(s); find<W>(s, &name).map!(|i| s.modules[i])
}
public fun module_page(s: &Soul, offset: u64, limit: u64): vector<Descriptor> {
    ready(s); assert!(limit <= MAX_MODULES && offset <= s.modules.length(), EInput);
    let end = if (limit < s.modules.length() - offset) offset + limit else s.modules.length();
    let mut result = vector[]; let mut i = offset;
    while (i < end) { result.push_back(s.modules[i]); i = i + 1 };
    result
}
public fun module_id(d: &Descriptor): ID { d.object }
public fun namespace(d: &Descriptor): TypeName { d.namespace }
public fun module_name(d: &Descriptor): vector<u8> { d.name }
public fun value_type(d: &Descriptor): TypeName { d.value_type }
public fun module_schema(d: &Descriptor): u16 { d.schema }
public fun removable(d: &Descriptor): bool { d.removable }
public fun body_hash(d: &Descriptor): vector<u8> { d.body_hash }
public fun semantic_hash(d: &Descriptor): vector<u8> { d.semantic_hash }
public fun manifest(s: &Soul): Manifest {
    ready(s); Manifest {
        domain: b"soulidity/standard/manifest/v1", soul: object::id(s), schema: s.schema,
        name: s.name, revision: s.revision, origin: s.origin, modules: s.modules,
    }
}
public fun manifest_hash(s: &Soul): vector<u8> { hash::sha3_256(bcs::to_bytes(&manifest(s))) }
public fun assert_manifest(s: &Soul, expected_revision: u64, expected_hash: vector<u8>) {
    ready(s); cas(s, expected_revision); hash32(&expected_hash);
    assert!(manifest_hash(s) == expected_hash, EInput)
}

/// Native whole-asset composition. Unnesting is always available to the actual
/// parent holder; no application can turn this namespace into a permanent lock.
public fun nest(s: &mut Soul, child: Soul, expected: u64) {
    let id = object::id(&child);
    assert!(id != object::id(s), EIdentity);
    let semantic = manifest_hash(&child);
    install(s, NestedSoulWitness {}, bcs::to_bytes(&id), child, 1, true, semantic, expected)
}
public fun nested(s: &Soul, child: ID): &Soul {
    borrow_module<NestedSoulWitness, Soul>(s, bcs::to_bytes(&child))
}
public fun unnest(s: &mut Soul, child: ID, expected: u64): Soul {
    uninstall<NestedSoulWitness, Soul>(s, bcs::to_bytes(&child), expected)
}
/// PTB-compatible value path. No mutable child/root UID or reference escapes;
/// edited child must return under the same parent with the same object ID.
public fun begin_nested_update(s: &mut Soul, child: ID, expected: u64): (Soul, Edit<NestedSoulWitness, Soul>) {
    begin_update(s, NestedSoulWitness {}, bcs::to_bytes(&child), expected)
}
public fun commit_nested_update(s: &mut Soul, ticket: Edit<NestedSoulWitness, Soul>, child: Soul) {
    let semantic = manifest_hash(&child);
    commit_update(s, ticket, NestedSoulWitness {}, child, 1, semantic)
}
