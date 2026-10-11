#[test_only]
module soulidity_standard::publisher_tests;
use sui::test_scenario;
use sui::package::{Self,Publisher};
use sui::transfer_policy;
use soulidity_standard::soul::{Self,Soul};

#[test]
fun standard_init_creates_package_publisher_and_real_policy_constructor(){
    let mut s=test_scenario::begin(@0xa);soul::init_for_testing(s.ctx());s.next_tx(@0xa);
    let p:Publisher=s.take_from_sender();
    assert!(package::from_package<Soul>(&p) && package::from_module<Soul>(&p),0);
    let(policy,cap)=transfer_policy::new<Soul>(&p,s.ctx());
    transfer::public_share_object(policy);transfer::public_transfer(cap,@0xa);s.return_to_sender(p);s.end();
}
#[test,expected_failure(abort_code=0,location=sui::transfer_policy)]
fun unrelated_package_publisher_cannot_create_standard_policy(){
    let mut s=test_scenario::begin(@0xa);
    let p=package::test_claim(std::string::utf8(b"unrelated"),s.ctx());
    let(policy,cap)=transfer_policy::new<Soul>(&p,s.ctx());
    transfer::public_share_object(policy);transfer::public_transfer(cap,@0xa);package::burn_publisher(p);s.end();
}
