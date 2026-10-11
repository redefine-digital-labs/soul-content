/// Immutable content policy snapshots and stable, pre-encryptable Seal namespaces.
module soulidity_content::document;
use std::bcs;
use soulidity_content_kinds::document_policy;
use std::string::{Self,String};
use soulidity_content_kinds::content_kind_registry::{Self as kind_registry,KindDescriptor};
use soulidity_content::storage::Reference;
const EName:u64=1;
const ERead:u64=2;
const EOperation:u64=3;
const EEnvelope:u64=4;
const EDeleted:u64=5;
const EPurge:u64=6;
const EKey:u64=7;
public struct Record has copy,drop,store {
    kind:u32,name:String,version:u64,reference:Reference,read_mask:u64,op_mask:u64,
    scope:u64,download_policy:u8,nonce:vector<u8>,envelope:vector<u8>,
    deleted:bool,purged:bool,created_at_ms:u64,seal_namespace:Option<vector<u8>>,
}
public struct Namespace has copy,drop,store {
    domain:vector<u8>,schema:u16,content:ID,kind:u32,name:String,version:u64,nonce:vector<u8>,
}
public fun soul_doc_name():String{ document_policy::soul_doc_name() }
public fun memory_name():String{ document_policy::memory_name() }
public fun assert_name(kind:u32,name:&String) { document_policy::assert_name(kind,name) }
public fun namespace(content:ID,kind:u32,name:String,version:u64,nonce:vector<u8>):vector<u8> {
    assert_name(kind,&name);assert!(nonce.length()==16,EKey);
    bcs::to_bytes(&Namespace{domain:b"soulidity-content",schema:1,content,kind,name,version,nonce})
}
public fun new(d:&KindDescriptor,name:String,version:u64,reference:Reference,read_mask:u64,download_policy:u8,nonce:vector<u8>,envelope:vector<u8>,created_at_ms:u64,initial:bool):Record {
    let kind=kind_registry::descriptor_kind(d);assert_name(kind,&name);
    assert!(!kind_registry::descriptor_deprecated(d),EOperation);
    let op_mask=kind_registry::descriptor_op_mask(d);
    if(initial)assert!(kind==0 && version==0,EOperation)
    else assert!((op_mask & kind_registry::op_append())!=0,EOperation);
    assert_read_policy(d,read_mask,download_policy);
    assert!(nonce.length()==16 && !envelope.is_empty() && envelope.length()<=65536,EEnvelope);
    Record{kind,name,version,reference,read_mask,op_mask,scope:kind_registry::descriptor_default_grant_scope_mask(d),download_policy,nonce,envelope,deleted:false,purged:false,created_at_ms,seal_namespace:option::none()}
}
/// Data construction only, never permission to append to an existing library.
/// The founding library's linear ticket confines this bypass to initial mint.
/// Original SOUL_DOC/MEMORY are owner+grant, even when APPEND is restricted.
public fun new_initial_invariant(d:&KindDescriptor,name:String,version:u64,reference:Reference,read_mask:u64,download_policy:u8,nonce:vector<u8>,envelope:vector<u8>,created_at_ms:u64):Record {
    let kind=kind_registry::descriptor_kind(d);assert!(kind==0 || kind==1,EOperation);
    assert_name(kind,&name);assert!(!kind_registry::descriptor_deprecated(d),EOperation);
    if(kind==0)assert!(version==0,EOperation);
    assert!(read_mask==(kind_registry::read_owner() | kind_registry::read_grant()),ERead);
    assert_read_policy(d,read_mask,download_policy);
    assert!(nonce.length()==16 && !envelope.is_empty() && envelope.length()<=65536,EEnvelope);
    Record{kind,name,version,reference,read_mask,op_mask:kind_registry::descriptor_op_mask(d),scope:kind_registry::descriptor_default_grant_scope_mask(d),download_policy,nonce,envelope,deleted:false,purged:false,created_at_ms,seal_namespace:option::none()}
}
public fun kind(r:&Record):u32{r.kind}
public fun name(r:&Record):String{r.name}
public fun version(r:&Record):u64{r.version}
public fun reference(r:&Record):&Reference{&r.reference}
public fun scope(r:&Record):u64{r.scope}
public fun created_at_ms(r:&Record):u64{r.created_at_ms}
public fun op_mask(r:&Record):u64{r.op_mask}
public fun nonce(r:&Record):vector<u8>{r.nonce}
public fun read_mask(r:&Record):u64{r.read_mask}
public fun download_policy(r:&Record):u8{r.download_policy}
public fun envelope(r:&Record):&vector<u8>{&r.envelope}
public fun deleted(r:&Record):bool{r.deleted}
public fun purged(r:&Record):bool{r.purged}
public fun seal_id(content:ID,r:&Record):vector<u8>{if(r.seal_namespace.is_some())*r.seal_namespace.borrow() else namespace(content,r.kind,r.name,r.version,r.nonce)}
public fun bind_initial_namespace(r:&mut Record,id:vector<u8>){assert!(r.version==0 && r.seal_namespace.is_none(),EKey);r.seal_namespace.fill(id)}
public fun assert_read_policy(d:&KindDescriptor,read_mask:u64,download_policy:u8) { document_policy::assert_read_policy(d,read_mask,download_policy) }
public fun assert_live(r:&Record){assert!(!r.deleted && !r.purged,EDeleted)}
public fun assert_read(r:&Record,mode:u64){assert_live(r);assert!((r.read_mask & mode)==mode,ERead)}
public fun assert_operation(r:&Record,op:u64){assert!((r.op_mask & op)==op,EOperation)}
public fun mark_deleted(r:&mut Record) {assert_live(r);assert_operation(r,kind_registry::op_delete());r.deleted=true}
public fun mark_purged(r:&mut Record) {assert!(r.deleted && !r.purged,EPurge);assert_operation(r,kind_registry::op_purge());r.purged=true;r.envelope=vector[]}
