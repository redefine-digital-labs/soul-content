/// Canonical pure names and descriptor-based read-policy validation.
module soulidity_content_kinds::document_policy;
use std::string::{Self,String};
use soulidity_content_kinds::content_kind_registry::{Self as kind_registry,KindDescriptor};
const EName:u64=1;const ERead:u64=2;const EOperation:u64=3;
public fun soul_doc_name():String{string::utf8(b"soul")}
public fun memory_name():String{string::utf8(b"default")}
public fun assert_name(kind:u32,name:&String) {
    let bytes=string::as_bytes(name);
    assert!(bytes.length()>0 && bytes.length()<=32,EName);
    bytes.do_ref!(|b| assert!((*b>=97 && *b<=122) || (*b>=48 && *b<=57) || *b==95 || *b==45,EName));
    if(kind==0)assert!(*name==soul_doc_name(),EName);
    if(kind==1)assert!(*name==memory_name(),EName);
}
public fun assert_read_policy(d:&KindDescriptor,read_mask:u64,download_policy:u8) {
    assert!(!kind_registry::descriptor_deprecated(d),EOperation);
    let allowed=kind_registry::descriptor_read_mode_mask(d);
    assert!(read_mask>0 && (read_mask & allowed)==read_mask && (read_mask & kind_registry::read_owner())!=0,ERead);
    assert!(if(kind_registry::descriptor_requires_download_policy(d))download_policy<=2 else download_policy==0,ERead);
    if((read_mask & kind_registry::read_public())!=0)assert!(download_policy==0,ERead);
}
