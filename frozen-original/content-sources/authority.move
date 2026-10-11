/// Typed application authority for content libraries. This is not an owner
/// attestation: the application must prove current custody at its user entry.
module soulidity_content::authority;
use std::type_name::{Self,TypeName};
use soulidity_standard::soul::Soul;
const EOperator:u64=1;
public struct Controller has store {operator:TypeName,parent:ID,root:ID}
/// A dedicated private marker is required; copyable public metadata from the
/// same application module is deliberately insufficient.
public fun bind<W:drop,P:key>(_w:W,parent:&P,root:&Soul):Controller{
    let w=type_name::with_original_ids<W>();let p=type_name::with_original_ids<P>();
    assert!(!w.is_primitive() && !p.is_primitive(),EOperator);
    assert!(w.address_string()==p.address_string() && w.module_string()==p.module_string() && *w.datatype_string().as_bytes()==b"ContentOperator",EOperator);
    Controller{operator:w,parent:object::id(parent),root:object::id(root)}
}
/// Only the same original application module can manufacture the bound marker.
/// Do not expose its constructor through the application public API.
public fun assert_operator<W:drop>(_w:W,c:&Controller){assert!(type_name::with_original_ids<W>()==c.operator,EOperator)}
public fun parent(c:&Controller):ID{c.parent}
public fun root(c:&Controller):ID{c.root}
public fun operator(c:&Controller):TypeName{c.operator}
