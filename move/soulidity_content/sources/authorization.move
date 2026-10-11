/// Delegations belong to an application controller's actual authorization object.
/// Native Soul custody is checked by its application entry, never by copied records.
module soulidity_content::authorization;
use std::bcs;
use sui::table::{Self,Table};
use sui::clock::{Self,Clock};
use sui::event;
use std::hash;
use soulidity_content::permissions;
const EGrantee:u64=1;const EScope:u64=2;const EExpiry:u64=3;const ECapacity:u64=4;
const ESnapshot:u64=5;const EGrant:u64=6;const ERemoveAll:u64=7;const EBatch:u64=8;
const MAX_CAPACITY:u64=10000;
public struct Authorization has key,store {id:UID,controller:soulidity_content::authority::Controller,root:ID,generation:u64,capacity:u64,count:u64,next_sequence:u64,grants:Table<address,Grant>}
public struct Grant has copy,drop,store {root:ID,version:u16,sequence:u64,issuer:address,grantee:address,scope:u64,expiry:Option<u64>,generation:u64}
public struct CleanupTarget has copy,drop,store {grantee:address,snapshot:Option<vector<u8>>}
public struct GrantChanged has copy,drop {root:ID,generation:u64,grantee:address,old:Option<vector<u8>>,new:Option<vector<u8>>,operation:u8}
public struct CapacityChanged has copy,drop {root:ID,old:u64,new:u64}
public struct GenerationChanged has copy,drop {root:ID,old:u64,new:u64}
public fun new<W:drop,P:key>(w:W,parent:&P,root:&soulidity_standard::soul::Soul,ctx:&mut TxContext):Authorization {
    let root_id=object::id(root);
    Authorization{controller:soulidity_content::authority::bind(w,parent,root),id:object::new(ctx),root:root_id,generation:0,capacity:1,count:0,next_sequence:0,grants:table::new(ctx)}
}
public fun generation(a:&Authorization):u64{a.generation}
public fun capacity(a:&Authorization):u64{a.capacity}
/// Current-generation physical count. Expired entries count until cleanup.
public fun count(a:&Authorization):u64{a.count}
public fun max_capacity():u64{MAX_CAPACITY}
public fun protocol_version():u16{1}
public fun grant(a:&Authorization,grantee:address):Option<Grant>{if(a.grants.contains(grantee))option::some(*a.grants.borrow(grantee)) else option::none()}
public fun grant_hash(a:&Authorization,grantee:address):Option<vector<u8>>{let g=grant(a,grantee);if(g.is_some())option::some(hash(g.borrow())) else option::none()}
public fun hash(g:&Grant):vector<u8>{let bytes=b"soulidity-grant-v1";let mut bytes=bytes;bytes.append(bcs::to_bytes(g));hash::sha2_256(bytes)}
public fun root(g:&Grant):ID{g.root}
public fun version(g:&Grant):u16{g.version}
public fun module_root(a:&Authorization):ID{a.root}
public fun sequence(g:&Grant):u64{g.sequence}
public fun issuer(g:&Grant):address{g.issuer}
public fun grantee(g:&Grant):address{g.grantee}
public fun scope(g:&Grant):u64{g.scope}
/// Read-only metadata query, never a standalone access approval.
public fun has_scope(g:&Grant,required:u64):bool{required!=0 && required<=15 && (g.scope & required)==required}
public fun expiry(g:&Grant):Option<u64>{g.expiry}
public fun grant_generation(g:&Grant):u64{g.generation}
fun internal_live(a:&Authorization,grantee:address,owner:address,clock:&Clock):bool {
    let g=grant(a,grantee);g.is_some() && is_live(a,g.borrow(),owner,clock)
}
fun is_live(a:&Authorization,g:&Grant,owner:address,clock:&Clock):bool{g.root==a.root && g.generation==a.generation && g.issuer==owner && (g.expiry.is_none() || *g.expiry.borrow()>clock::timestamp_ms(clock))}
fun internal_assert_snapshot(a:&Authorization,expected_generation:u64,expected_capacity:u64,expected_count:u64,grantee:address,expected_slot:Option<vector<u8>>,expected_live:bool,owner:address,clock:&Clock) {
    assert!(a.generation==expected_generation && a.capacity==expected_capacity && a.count==expected_count && grant_hash(a,grantee)==expected_slot && internal_live(a,grantee,owner,clock)==expected_live,ESnapshot)
}
fun internal_assert_preserves_active_scopes(a:&Authorization,grantee:address,desired:u64,owner:address,clock:&Clock) {
    assert_scope(desired);if(internal_live(a,grantee,owner,clock)){let g=grant(a,grantee).destroy_some();assert!((desired & g.scope)==g.scope,ESnapshot)}
}
public fun cleanup_target(grantee:address,snapshot:Option<vector<u8>>):CleanupTarget{if(snapshot.is_some())assert_digest(snapshot.borrow());CleanupTarget{grantee,snapshot}}
fun internal_issue(a:&mut Authorization,grantee:address,scope:u64,expiry:Option<u64>,expected_slot:Option<vector<u8>>,clock:&Clock,ctx:&TxContext):u64 {
    assert!(grantee!=@0x0 && grantee!=ctx.sender(),EGrantee);assert_scope(scope);if(expiry.is_some())assert!(*expiry.borrow()>clock::timestamp_ms(clock),EExpiry);
    assert_slot(a,grantee,expected_slot);let old=grant_hash(a,grantee);
    if(a.grants.contains(grantee))remove(a,grantee);
    assert!(a.count < a.capacity,ECapacity);let sequence=a.next_sequence;a.next_sequence=sequence+1;
    let g=Grant{root:a.root,version:1,sequence,issuer:ctx.sender(),grantee,scope,expiry,generation:a.generation};let new=hash(&g);
    a.grants.add(grantee,g);a.count=a.count+1;event::emit(GrantChanged{root:a.root,generation:a.generation,grantee,old,new:option::some(new),operation:if(old.is_some())1 else 0});sequence
}
fun internal_revoke(a:&mut Authorization,grantee:address,expected_slot:vector<u8>) {
    assert_digest(&expected_slot);assert_slot(a,grantee,option::some(expected_slot));assert!(a.grants.contains(grantee),EGrant);
    let old=grant_hash(a,grantee);remove(a,grantee);event::emit(GrantChanged{root:a.root,generation:a.generation,grantee,old,new:option::none(),operation:2})
}
fun internal_revoke_scope(a:&mut Authorization,grantee:address,revoked:u64,expected_slot:vector<u8>,clock:&Clock,ctx:&TxContext):u64 {
    assert_scope(revoked);assert_slot(a,grantee,option::some(expected_slot));assert!(internal_live(a,grantee,ctx.sender(),clock),EGrant);
    let g=grant(a,grantee).destroy_some();let retained=g.scope ^ (g.scope & revoked);assert!(retained!=0,ERemoveAll);
    internal_issue(a,grantee,retained,g.expiry,option::some(expected_slot),clock,ctx)
}
fun internal_set_capacity(a:&mut Authorization,capacity:u64,expected_capacity:u64) {
    assert!(a.capacity==expected_capacity,ESnapshot);assert!(capacity<=MAX_CAPACITY && capacity>=a.count,ECapacity);let old=a.capacity;a.capacity=capacity;event::emit(CapacityChanged{root:a.root,old,new:capacity})
}
fun internal_cleanup(a:&mut Authorization,targets:vector<CleanupTarget>,clock:&Clock,ctx:&TxContext):u64 {
    assert!(targets.length()<=256,EBatch);let mut seen=vector[];
    targets.do_ref!(|t|{assert!(!seen.contains(&t.grantee),EBatch);seen.push_back(t.grantee);assert_slot(a,t.grantee,t.snapshot)});
    let mut removed=0;targets.do_ref!(|t|{if(a.grants.contains(t.grantee) && !internal_live(a,t.grantee,ctx.sender(),clock)){let old=grant_hash(a,t.grantee);remove(a,t.grantee);removed=removed+1;event::emit(GrantChanged{root:a.root,generation:a.generation,grantee:t.grantee,old,new:option::none(),operation:3})}});removed
}
/// Constant work invalidation. Old physical rows can be explicitly cleaned or
/// replaced; their generation is never active and never consumes new capacity.
fun internal_clear(a:&mut Authorization) {
    let old=a.generation;a.generation=old+1;a.count=0;event::emit(GenerationChanged{root:a.root,old,new:a.generation})
}
fun internal_permits(a:&Authorization,owner:address,grantee:address,required:u64,clock:&Clock):bool {
    assert_scope(required);let g=grant(a,grantee);g.is_some() && is_live(a,g.borrow(),owner,clock) && (g.borrow().scope & required)==required
}
fun assert_scope(scope:u64){let all=permissions::scope_seal() | permissions::scope_memory() | permissions::scope_skills() | permissions::scope_assets();assert!(scope!=0 && (scope & all)==scope,EScope)}
fun assert_slot(a:&Authorization,grantee:address,snapshot:Option<vector<u8>>){assert!(grant_hash(a,grantee)==snapshot,ESnapshot)}
fun remove(a:&mut Authorization,grantee:address){let g=a.grants.remove(grantee);if(g.generation==a.generation)a.count=a.count-1}

/// Cross-package methods require this instance's private application operator.
public fun live<W:drop>(w:W,a:&Authorization,grantee:address,owner:address,clock:&Clock):bool {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_live(a,grantee,owner,clock)
}

public fun assert_snapshot<W:drop>(w:W,a:&Authorization,expected_generation:u64,expected_capacity:u64,expected_count:u64,grantee:address,expected_slot:Option<vector<u8>>,expected_live:bool,owner:address,clock:&Clock) {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_assert_snapshot(a,expected_generation,expected_capacity,expected_count,grantee,expected_slot,expected_live,owner,clock)
}

public fun assert_preserves_active_scopes<W:drop>(w:W,a:&Authorization,grantee:address,desired:u64,owner:address,clock:&Clock) {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_assert_preserves_active_scopes(a,grantee,desired,owner,clock)
}

public fun issue<W:drop>(w:W,a:&mut Authorization,grantee:address,scope:u64,expiry:Option<u64>,expected_slot:Option<vector<u8>>,clock:&Clock,ctx:&TxContext):u64 {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_issue(a,grantee,scope,expiry,expected_slot,clock,ctx)
}

public fun revoke<W:drop>(w:W,a:&mut Authorization,grantee:address,expected_slot:vector<u8>) {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_revoke(a,grantee,expected_slot)
}

public fun revoke_scope<W:drop>(w:W,a:&mut Authorization,grantee:address,revoked:u64,expected_slot:vector<u8>,clock:&Clock,ctx:&TxContext):u64 {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_revoke_scope(a,grantee,revoked,expected_slot,clock,ctx)
}

public fun set_capacity<W:drop>(w:W,a:&mut Authorization,capacity:u64,expected_capacity:u64) {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_set_capacity(a,capacity,expected_capacity)
}

public fun cleanup<W:drop>(w:W,a:&mut Authorization,targets:vector<CleanupTarget>,clock:&Clock,ctx:&TxContext):u64 {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_cleanup(a,targets,clock,ctx)
}

public fun clear<W:drop>(w:W,a:&mut Authorization) {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_clear(a)
}

public fun permits<W:drop>(w:W,a:&Authorization,owner:address,grantee:address,required:u64,clock:&Clock):bool {
    soulidity_content::authority::assert_operator(w,&a.controller);
    internal_permits(a,owner,grantee,required,clock)
}

fun assert_digest(value:&vector<u8>){assert!(value.length()==32,EScope)}
