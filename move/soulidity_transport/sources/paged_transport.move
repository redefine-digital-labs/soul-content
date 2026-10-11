/// Append-only indexed metadata. A large inventory never grows one inline object.
/// Public builders mutate only caller-owned copyable metadata; owning modules keep installed stores private.
module soulidity_transport::paged_transport;
use std::bcs;
use sui::table::{Self,Table};
const ECapacity:u64=1;const EIndex:u64=2;
const MAX_ROWS:u64=512;
// Reserve space for dynamic_field::Field UID/key and vector length prefix.
const PAGE_BYTES:u64=196608;
const PAGE_ROWS:u64=32;
public struct Location has copy,drop,store {page:u64,index:u64}
public struct Store<T:copy+drop+store> has store {pages:Table<u64,vector<T>>,locations:vector<Location>,page_count:u64,last_bytes:u64}
public fun new<T:copy+drop+store>(ctx:&mut TxContext):Store<T>{Store{pages:table::new(ctx),locations:vector[],page_count:0,last_bytes:0}}
public fun length<T:copy+drop+store>(s:&Store<T>):u64{s.locations.length()}
public fun pages<T:copy+drop+store>(s:&Store<T>):u64{s.page_count}
public fun get<T:copy+drop+store>(s:&Store<T>,index:u64):&T{assert!(index < length(s),EIndex);let at=s.locations[index];&s.pages.borrow(at.page)[at.index]}
public fun values<T:copy+drop+store>(s:&Store<T>):vector<T>{
    // Private append-only locations enumerate these pages in insertion order.
    // Borrow each actual page once instead of reloading it for every row.
    let mut values=vector[];let mut page=0;
    while(page < s.page_count){s.pages.borrow(page).do_ref!(|value|values.push_back(*value));page=page+1};values
}
/// Read an exact insertion-order interval across row- or byte-limited pages.
/// Returned copies are metadata, never an installed Store or custody proof.
public fun range<T:copy+drop+store>(s:&Store<T>,start:u64,count:u64):vector<T>{
    let n=length(s);assert!(start<=n && count<=n-start,EIndex);
    let mut values=vector[];let mut next=start;let end=start+count;
    while(next < end){
        let at=s.locations[next];let page=s.pages.borrow(at.page);let mut offset=at.index;
        while(offset < page.length() && next < end){values.push_back(page[offset]);offset=offset+1;next=next+1}
    };values
}
public fun append<T:copy+drop+store>(s:&mut Store<T>,value:T):u64{
    assert!(length(s) < MAX_ROWS,ECapacity);let bytes=bcs::to_bytes(&value).length();assert!(bytes<=PAGE_BYTES,ECapacity);
    if(s.page_count==0 || s.last_bytes+bytes>PAGE_BYTES || s.pages.borrow(s.page_count-1).length()>=PAGE_ROWS){
        s.pages.add(s.page_count,vector[]);s.page_count=s.page_count+1;s.last_bytes=0
    };
    let page=s.page_count-1;let index=s.pages.borrow(page).length();s.pages.borrow_mut(page).push_back(value);s.last_bytes=s.last_bytes+bytes;
    let record=length(s);s.locations.push_back(Location{page,index});record
}
public fun from_values<T:copy+drop+store>(values:vector<T>,ctx:&mut TxContext):Store<T>{let mut s=new(ctx);values.do!(|value|{let _=append(&mut s,value);});s}
public fun destroy<T:copy+drop+store>(s:Store<T>){let Store{mut pages,locations:_,page_count,last_bytes:_}=s;let mut i=0;while(i < page_count){pages.remove(i);i=i+1};pages.destroy_empty()}
