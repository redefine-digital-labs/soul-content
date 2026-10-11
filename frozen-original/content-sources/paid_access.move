/// Owner-revocable, per-kind subscriptions. Never a transferable permanent license.
module soulidity_content::paid_access;
/// Private values are constructed and consumed only inside this producer.
public struct PaidAuthority1 has drop {}
public struct PaidRevision1 has drop {}
public struct PAID_ACCESS has drop {}
fun init(w:PAID_ACCESS,ctx:&mut TxContext){sui::package::claim_and_keep(w,ctx)}

use std::bcs;
use sui::table::{Self,Table};
use sui::clock::{Self,Clock};
use sui::coin::{Self,Coin};
use sui::event;
use soulidity_content::kind_registry::{Self,KindRegistry};
use std::hash;
use soulidity_foundation::economics::{Self,Config};
const EConfig:u64=1;const ERevision:u64=2;const EEntry:u64=3;const EReplay:u64=4;const EAccess:u64=5;
public struct Ledger has key,store {
    id:UID,controller:soulidity_content::authority::Controller,root:ID,protocol:ID,revision:u64,offers:Table<u32,Offer>,entries:Table<BuyerKey,Entry>,attempts:Table<AttemptKey,Receipt>,
}
public struct Offer has copy,drop,store {issuer:address,generation:u64,price:u64,scope:u64,duration:Option<u64>,revision:u64}
public struct BuyerKey has copy,drop,store {kind:u32,buyer:address}
public struct Entry has copy,drop,store {issuer:address,generation:u64,scope:u64,expiry:Option<u64>,revision:u64}
public struct AttemptKey has copy,drop,store {buyer:address,attempt:vector<u8>}
public struct Receipt has copy,drop,store {kind:u32,quote:vector<u8>,entry_hash:vector<u8>,price:u64,total:u64,platform_fee:u64,fee_revision:u64,platform_recipient:address,beneficiary:address}
public struct Quote has copy,drop,store {domain:vector<u8>,root:ID,protocol:ID,kind:u32,offer:Offer}
public struct Updated has copy,drop {root:ID,kind:u32,buyer:Option<address>,revision:u64,operation:u8,entry:Option<Entry>}
public fun new<W:drop,P:key>(w:W,parent:&P,root:&soulidity_standard::soul::Soul,protocol:ID,ctx:&mut TxContext):Ledger {
    let root_id=object::id(root);
    Ledger{controller:soulidity_content::authority::bind(w,parent,root),id:object::new(ctx),root:root_id,protocol,revision:0,offers:table::new(ctx),entries:table::new(ctx),attempts:table::new(ctx)}
}
public fun revision(l:&Ledger):u64{l.revision}
public fun offer(l:&Ledger,kind:u32):Option<Offer>{if(l.offers.contains(kind))option::some(*l.offers.borrow(kind)) else option::none()}
public fun entry(l:&Ledger,kind:u32,buyer:address):Option<Entry>{let k=BuyerKey{kind,buyer};if(l.entries.contains(k))option::some(*l.entries.borrow(k)) else option::none()}
public fun entry_hash(l:&Ledger,kind:u32,buyer:address):Option<vector<u8>> {let e=entry(l,kind,buyer);if(e.is_some())option::some(hash::sha2_256(bcs::to_bytes(e.borrow()))) else option::none()}
public fun expires(e:&Entry):Option<u64>{e.expiry}
public fun receipt(l:&Ledger,buyer:address,attempt:vector<u8>):Option<Receipt>{let k=AttemptKey{buyer,attempt};if(l.attempts.contains(k))option::some(*l.attempts.borrow(k)) else option::none()}
public fun total<C>(l:&Ledger,cfg:&Config<C>,kind:u32):u64{assert!(object::id(cfg)==l.protocol,EConfig);economics::primary_total(cfg,offer(l,kind).destroy_some().price)}
public fun receipt_price(r:&Receipt):u64{r.price}
public fun receipt_total(r:&Receipt):u64{r.total}
public fun receipt_fee(r:&Receipt):u64{r.platform_fee}
public fun receipt_fee_revision(r:&Receipt):u64{r.fee_revision}
public fun receipt_beneficiary(r:&Receipt):address{r.beneficiary}
public fun receipt_platform_recipient(r:&Receipt):address{r.platform_recipient}
public fun quote(l:&Ledger,kind:u32):vector<u8> {
    let offer=offer(l,kind).destroy_some();hash::sha2_256(bcs::to_bytes(&Quote{domain:b"soulidity-paid-kind",root:l.root,protocol:l.protocol,kind,offer}))
}
fun assert_revision(l:&Ledger,expected:u64){assert!(l.revision==expected,ERevision)}
fun assert_kind(registry:&KindRegistry,kind:u32,scope:u64) {
    let d=kind_registry::borrow_descriptor(registry,kind);
    assert!(!kind_registry::descriptor_deprecated(d) && (kind_registry::descriptor_read_mode_mask(d) & kind_registry::read_paid())!=0 && scope>0 && scope==kind_registry::descriptor_default_grant_scope_mask(d),EConfig)
}
fun internal_configure(l:&mut Ledger,registry:&KindRegistry,kind:u32,price:u64,scope:u64,duration:Option<u64>,owner:address,generation:u64,expected:u64) {
    assert_revision(l,expected);assert_kind(registry,kind,scope);
    if(duration.is_some())assert!(*duration.borrow()>0,EConfig);
    let offer=Offer{issuer:owner,generation,price,scope,duration,revision:l.revision+1};
    if(l.offers.contains(kind))*l.offers.borrow_mut(kind)=offer else l.offers.add(kind,offer);
    changed(l,kind,option::none(),0,option::none())
}
/// Removing a sale offer does not revoke a previously bought entry.
fun internal_remove_offer(l:&mut Ledger,kind:u32,expected:u64) {
    assert_revision(l,expected);assert!(l.offers.contains(kind),EConfig);l.offers.remove(kind);changed(l,kind,option::none(),1,option::none())
}
fun internal_buy<C>(l:&mut Ledger,cfg:&mut Config<C>,kind:u32,owner:address,generation:u64,expected_quote:vector<u8>,expected_entry:Option<vector<u8>>,fee_revision:u64,quote_expiry:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    assert!(object::id(cfg)==l.protocol,EConfig);economics::assert_primary_live(cfg,fee_revision,quote_expiry,clock);assert_digest(&attempt);
    let buyer=ctx.sender();assert!(buyer!=owner,EEntry);let request=AttemptKey{buyer,attempt};assert!(!l.attempts.contains(request),EReplay);
    assert!(entry_hash(l,kind,buyer)==expected_entry,ERevision);
    assert!(quote(l,kind)==expected_quote,ERevision);let o=offer(l,kind).destroy_some();
    assert!(o.issuer==owner && o.generation==generation,EConfig);let total=economics::primary_total(cfg,o.price);assert!(coin::value(&payment)==total,EConfig);
    let now=clock::timestamp_ms(clock);let mut base=now;
    let previous=entry(l,kind,buyer);
    if(previous.is_some()) {
        let prev=previous.borrow();
        if(prev.issuer==owner && prev.generation==generation) {
            assert!(prev.expiry.is_some(),EEntry);base=base.max(*prev.expiry.borrow())
        }
    };
    let expiry=if(o.duration.is_some())option::some(base+*o.duration.borrow()) else option::none();
    let e=Entry{issuer:owner,generation,scope:o.scope,expiry,revision:l.revision+1};let k=BuyerKey{kind,buyer};
    if(l.entries.contains(k))*l.entries.borrow_mut(k)=e else l.entries.add(k,e);
    let hash=entry_hash(l,kind,buyer).destroy_some();l.attempts.add(request,Receipt{kind,quote:expected_quote,entry_hash:hash,price:o.price,total,platform_fee:economics::primary_fee(cfg,o.price),fee_revision,platform_recipient:economics::recipient(cfg),beneficiary:owner});
    economics::primary_additional<C,PaidAuthority1,PaidRevision1>(cfg,PaidAuthority1{},PaidRevision1{},payment,o.price,owner,l.root,attempt,ctx);changed(l,kind,option::some(buyer),2,option::some(e))
}
fun internal_add(l:&mut Ledger,registry:&KindRegistry,kind:u32,buyer:address,scope:u64,expiry:Option<u64>,owner:address,generation:u64,expected:u64,expected_entry:Option<vector<u8>>,clock:&Clock) {
    assert_revision(l,expected);assert_kind(registry,kind,scope);assert!(buyer!=@0x0 && buyer!=owner,EEntry);
    if(expiry.is_some())assert!(*expiry.borrow()>clock::timestamp_ms(clock),EEntry);
    assert!(entry_hash(l,kind,buyer)==expected_entry,ERevision);
    let previous=entry(l,kind,buyer);if(previous.is_some()){let prev=previous.borrow();assert!(prev.issuer!=owner || prev.generation!=generation || prev.expiry.is_some(),EEntry)};
    let e=Entry{issuer:owner,generation,scope,expiry,revision:l.revision+1};let k=BuyerKey{kind,buyer};
    if(l.entries.contains(k))*l.entries.borrow_mut(k)=e else l.entries.add(k,e);
    changed(l,kind,option::some(buyer),3,option::some(e))
}
fun internal_revoke(l:&mut Ledger,kind:u32,buyer:address,expected:u64,expected_entry:vector<u8>) {
    assert_revision(l,expected);assert!(entry_hash(l,kind,buyer)==option::some(expected_entry),ERevision);
    let k=BuyerKey{kind,buyer};assert!(l.entries.contains(k),EEntry);l.entries.remove(k);changed(l,kind,option::some(buyer),4,option::none())
}
fun internal_cleanup(l:&mut Ledger,kind:u32,buyer:address,owner:address,generation:u64,expected:u64,clock:&Clock) {
    assert_revision(l,expected);let e=entry(l,kind,buyer).destroy_some();
    assert!(e.issuer!=owner || e.generation!=generation || (e.expiry.is_some() && *e.expiry.borrow()<=clock::timestamp_ms(clock)),EEntry);
    l.entries.remove(BuyerKey{kind,buyer});changed(l,kind,option::some(buyer),5,option::none())
}
fun internal_assert_access(l:&Ledger,kind:u32,buyer:address,owner:address,generation:u64,scope:u64,clock:&Clock) {
    let e=entry(l,kind,buyer);assert!(e.is_some(),EAccess);let e=e.borrow();
    assert!(e.issuer==owner && e.generation==generation && scope>0 && (e.scope & scope)==scope,EAccess);
    if(e.expiry.is_some())assert!(*e.expiry.borrow()>clock::timestamp_ms(clock),EAccess)
}
fun changed(l:&mut Ledger,kind:u32,buyer:Option<address>,operation:u8,entry:Option<Entry>) {
    l.revision=l.revision+1;event::emit(Updated{root:l.root,kind,buyer,revision:l.revision,operation,entry})
}

public fun register<C>(cfg:&mut soulidity_foundation::economics::Config<C>,admin:&mut soulidity_foundation::economics::Admin,expected:u64,hash:vector<u8>,publisher:&sui::package::Publisher,cap:&sui::package::UpgradeCap){
    economics::register_role<C,PaidAuthority1,PaidRevision1>(cfg,admin,expected,hash,5,PaidAuthority1{},PaidRevision1{},publisher,cap)
}

/// Cross-package methods require this instance's private application operator.
public fun configure<W:drop>(w:W,l:&mut Ledger,registry:&KindRegistry,kind:u32,price:u64,scope:u64,duration:Option<u64>,owner:address,generation:u64,expected:u64) {
    soulidity_content::authority::assert_operator(w,&l.controller);
    internal_configure(l,registry,kind,price,scope,duration,owner,generation,expected)
}

public fun remove_offer<W:drop>(w:W,l:&mut Ledger,kind:u32,expected:u64) {
    soulidity_content::authority::assert_operator(w,&l.controller);
    internal_remove_offer(l,kind,expected)
}

public fun buy<W:drop,C>(w:W,l:&mut Ledger,cfg:&mut Config<C>,kind:u32,owner:address,generation:u64,expected_quote:vector<u8>,expected_entry:Option<vector<u8>>,fee_revision:u64,quote_expiry:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    soulidity_content::authority::assert_operator(w,&l.controller);
    internal_buy<C>(l,cfg,kind,owner,generation,expected_quote,expected_entry,fee_revision,quote_expiry,attempt,payment,clock,ctx)
}

public fun add<W:drop>(w:W,l:&mut Ledger,registry:&KindRegistry,kind:u32,buyer:address,scope:u64,expiry:Option<u64>,owner:address,generation:u64,expected:u64,expected_entry:Option<vector<u8>>,clock:&Clock) {
    soulidity_content::authority::assert_operator(w,&l.controller);
    internal_add(l,registry,kind,buyer,scope,expiry,owner,generation,expected,expected_entry,clock)
}

public fun revoke<W:drop>(w:W,l:&mut Ledger,kind:u32,buyer:address,expected:u64,expected_entry:vector<u8>) {
    soulidity_content::authority::assert_operator(w,&l.controller);
    internal_revoke(l,kind,buyer,expected,expected_entry)
}

public fun cleanup<W:drop>(w:W,l:&mut Ledger,kind:u32,buyer:address,owner:address,generation:u64,expected:u64,clock:&Clock) {
    soulidity_content::authority::assert_operator(w,&l.controller);
    internal_cleanup(l,kind,buyer,owner,generation,expected,clock)
}

public fun assert_access<W:drop>(w:W,l:&Ledger,kind:u32,buyer:address,owner:address,generation:u64,scope:u64,clock:&Clock) {
    soulidity_content::authority::assert_operator(w,&l.controller);
    internal_assert_access(l,kind,buyer,owner,generation,scope,clock)
}

fun assert_digest(value:&vector<u8>){assert!(value.length()==32,EConfig)}

#[test_only]
public fun bootstrap_for_testing<C>(cfg:&mut Config<C>,a:&mut soulidity_foundation::economics::Admin){economics::bootstrap_role_for_testing<C,PaidAuthority1,PaidRevision1>(cfg,a,5,PaidAuthority1{},PaidRevision1{})}
#[test_only]
public fun publisher_for_testing(ctx:&mut TxContext):sui::package::Publisher{sui::package::test_claim(PaidAuthority1{},ctx)}
