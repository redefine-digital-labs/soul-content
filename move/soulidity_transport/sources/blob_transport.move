/// Bounded actual Walrus objects under the caller's controlled native UID.
/// No UID is returned; obtaining a mutable parent UID remains its owner's job.
module soulidity_transport::blob_transport;
use sui::dynamic_object_field as dof;
use walrus::blob::Blob;
use walrus::system::{Self,System};
use soulidity_transport::storage_transport::{Self as storage,Reference};
const EBounds:u64=1;const EComplete:u64=2;
public struct BlobKey has copy,drop,store {kind:u8,index:u64}
public struct BlobPage has key,store {id:UID,blobs:vector<Blob>}
public fun add_document(parent:&mut UID,kind:u8,blob:Blob){assert!(kind < 2,EBounds);dof::add(parent,BlobKey{kind,index:0},blob)}
public fun append(parent:&mut UID,index:u64,blob:Blob,ctx:&mut TxContext){
    assert!(index < 500,EBounds);let key=BlobKey{kind:2,index:index/32};
    if(index%32==0)dof::add(parent,key,BlobPage{id:object::new(ctx),blobs:vector[]});
    let page:&mut BlobPage=dof::borrow_mut(parent,key);assert!(page.blobs.length()==index%32,EComplete);page.blobs.push_back(blob)
}
/// Cancellation consumes the oldest remaining element. The issuer prohibits
/// append/finish after cancellation and tracks the original absolute index.
public fun take(parent:&mut UID,index:u64):Blob{
    assert!(index < 500,EBounds);let key=BlobKey{kind:2,index:index/32};let page:&mut BlobPage=dof::borrow_mut(parent,key);let blob=page.blobs.remove(0);
    if(page.blobs.is_empty()){let BlobPage{id,blobs}=dof::remove(parent,key);blobs.destroy_empty();id.delete()};blob
}
public fun take_document(parent:&mut UID,kind:u8):Blob{assert!(kind < 2,EBounds);dof::remove(parent,BlobKey{kind,index:0})}
/// Mutating this caller-controlled Blob can invalidate availability. Native
/// issuers expose only authorized renewal, never their mutable custody UID.
public fun borrow_mut(parent:&mut UID,kind:u8,index:u64):&mut Blob{
    assert!((kind < 2 && index==0)||(kind==2 && index < 500),EBounds);
    if(kind < 2)dof::borrow_mut(parent,BlobKey{kind,index}) else {let page:&mut BlobPage=dof::borrow_mut(parent,BlobKey{kind:2,index:index/32});page.blobs.borrow_mut(index%32)}
}
/// All 500 identities/leases are checked against one actual immutable System
/// epoch within this function. No caller epoch or reusable proof is accepted.
public fun assert_current(parent:&UID,living:&Reference,manifest:&Reference,references:&vector<Reference>,system:&System){
    let n=references.length();assert!(n<=500,EBounds);let epoch=system::epoch(system);
    storage::assert_current_at_epoch(living,dof::borrow(parent,BlobKey{kind:0,index:0}),epoch);
    storage::assert_current_at_epoch(manifest,dof::borrow(parent,BlobKey{kind:1,index:0}),epoch);
    let mut i=0;
    while(i < n){let page:&BlobPage=dof::borrow(parent,BlobKey{kind:2,index:i/32});let size=page.blobs.length();
        assert!(size>0 && size<=32 && i+size<=n && (size==32 || i+size==n),EComplete);
        let mut j=0;while(j < size){storage::assert_current_at_epoch(&references[i],&page.blobs[j],epoch);i=i+1;j=j+1}
    }
}

/// Immutable current custody read. The owner must provide its own UID reference;
/// no mutable UID or raw-ID authority is created by this accessor.
public fun borrow(parent:&UID,kind:u8,index:u64):&Blob{
 assert!((kind < 2 && index==0)||(kind==2 && index < 500),EBounds);
 if(kind < 2)dof::borrow(parent,BlobKey{kind,index}) else {let page:&BlobPage=dof::borrow(parent,BlobKey{kind:2,index:index/32});page.blobs.borrow(index%32)}
}
