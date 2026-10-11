/// Typed Walrus certification and expiry, using Walrus epochs (not Sui epochs).
module soulidity_content::storage;
use walrus::blob::{Self,Blob};
use walrus::system::{Self,System};
const EUnavailable:u64=1;const EReference:u64=2;
/// SHA-256 is a publisher's byte commitment; certification proves availability
/// of the Blob ID, not equality between that SHA-256 and the Walrus root hash.
public struct Reference has copy,drop,store {
    object:ID,blob_id:u256,sha256:vector<u8>,bytes:u64,certified_epoch:u32,end_epoch:u32,
}
public fun certified(blob:&Blob,system:&System,sha256:vector<u8>):Reference {
    assert_digest(&sha256);
    assert!(blob::certified_epoch(blob).is_some() && !blob::is_deletable(blob),EUnavailable);
    let epoch=system::epoch(system);assert!(blob::end_epoch(blob)>epoch,EUnavailable);
    assert!(blob::size(blob)>0,EReference);
    assert!(blob::registered_epoch(blob)<=*blob::certified_epoch(blob).borrow() && *blob::certified_epoch(blob).borrow()<=epoch,EUnavailable);
    Reference{object:object::id(blob),blob_id:blob::blob_id(blob),sha256,bytes:blob::size(blob),certified_epoch:*blob::certified_epoch(blob).borrow(),end_epoch:blob::end_epoch(blob)}
}
/// Actual certification of each Blob; one epoch read during this invocation.
/// References remain copyable metadata and cannot substitute for later custody.
public fun certified_batch(blobs:&vector<Blob>,system:&System,hashes:&vector<vector<u8>>):vector<Reference>{
    let n=blobs.length();assert!(n==hashes.length(),EReference);let epoch=system::epoch(system);
    let mut references=vector[];let mut i=0;
    while(i < n){
        let blob=&blobs[i];let sha256=hashes[i];assert_digest(&sha256);
        assert!(blob::certified_epoch(blob).is_some() && !blob::is_deletable(blob) && blob::end_epoch(blob)>epoch,EUnavailable);
        assert!(blob::size(blob)>0,EReference);
        let certified_epoch=*blob::certified_epoch(blob).borrow();
        assert!(blob::registered_epoch(blob)<=certified_epoch && certified_epoch<=epoch,EUnavailable);
        references.push_back(Reference{object:object::id(blob),blob_id:blob::blob_id(blob),sha256,bytes:blob::size(blob),certified_epoch,end_epoch:blob::end_epoch(blob)});i=i+1
    };references
}
public fun assert_current(r:&Reference,blob:&Blob,system:&System) {
    assert!(object::id(blob)==r.object && blob::blob_id(blob)==r.blob_id && blob::size(blob)==r.bytes,EReference);
    assert!(blob::certified_epoch(blob).is_some() && !blob::is_deletable(blob),EUnavailable);
    // Both inequalities use the same actual immutable System input. No epoch
    // supplied by a caller or cached across transactions is accepted.
    let epoch=system::epoch(system);assert!(blob::end_epoch(blob)>epoch,EUnavailable);
    assert!(*blob::certified_epoch(blob).borrow()==r.certified_epoch && blob::registered_epoch(blob)<=r.certified_epoch && r.certified_epoch<=epoch,EUnavailable)
}
/// Validate every actual Blob against the same current immutable System input.
/// The epoch never escapes this invocation and cannot be reused after a later
/// System mutation in the same PTB. This returns no token or authorization.
public fun assert_current_batch(references:&vector<Reference>,blobs:&vector<Blob>,system:&System){
    let n=references.length();assert!(n==blobs.length(),EReference);
    let epoch=system::epoch(system);let mut i=0;
    while(i < n){
        let r=&references[i];let blob=&blobs[i];
        assert!(object::id(blob)==r.object && blob::blob_id(blob)==r.blob_id && blob::size(blob)==r.bytes,EReference);
        assert!(blob::certified_epoch(blob).is_some() && !blob::is_deletable(blob) && blob::end_epoch(blob)>epoch,EUnavailable);
        assert!(*blob::certified_epoch(blob).borrow()==r.certified_epoch && blob::registered_epoch(blob)<=r.certified_epoch && r.certified_epoch<=epoch,EUnavailable);
        i=i+1
    }
}
/// Package-internal only. Public validators obtain the actual epoch during
/// their synchronous call; foreign packages cannot submit a claimed epoch.
public(package) fun assert_current_at_epoch(r:&Reference,blob:&Blob,epoch:u32){
    assert!(object::id(blob)==r.object && blob::blob_id(blob)==r.blob_id && blob::size(blob)==r.bytes,EReference);
    assert!(blob::certified_epoch(blob).is_some() && !blob::is_deletable(blob) && blob::end_epoch(blob)>epoch,EUnavailable);
    assert!(*blob::certified_epoch(blob).borrow()==r.certified_epoch && blob::registered_epoch(blob)<=r.certified_epoch && r.certified_epoch<=epoch,EUnavailable)
}
public fun hash(r:&Reference):vector<u8>{r.sha256}
public fun bytes(r:&Reference):u64{r.bytes}
public fun blob_id(r:&Reference):u256{r.blob_id}
public fun object_id(r:&Reference):ID{r.object}

/// Certification-time snapshots. Renewed availability is checked against the stored Blob.
public fun certified_epoch(r:&Reference):u32{r.certified_epoch}
public fun original_end_epoch(r:&Reference):u32{r.end_epoch}


fun assert_digest(value:&vector<u8>){assert!(value.length()==32,EReference)}
