#[test_only]
module soulidity_v1::fixtures;
use std::string;
use sui::test_scenario::{Self,Scenario};
use sui::clock;
use sui::coin;
use soulidity_model::policy::{Self,Definition,Layout};
use soulidity_foundation::economics::{Self,Config,Authority};
use soulidity_v1::catalog::{Self,Product,Control};
use soulidity_v1::issuer::{Self,Build};
use soulidity_application::output::{Self,Intent,Policy};
use soulidity_content::kind_registry::{Self,KindRegistry};
use soulidity_content::document;
use soulidity_v1::storage_fixture;
use soulidity_visual::visual::{Self,Scene,Representation};
use walrus::system::System;
use sui::clock::Clock;
public struct USD has drop {}
public fun protocol_income(sc:&Scenario):u64{let cfg:Config<USD> = sc.take_shared();let n=soulidity_foundation::revenue::balance(economics::income(&cfg));test_scenario::return_shared(cfg);n}
public fun product_income(sc:&Scenario,product:ID):u64{let p:Product<USD> = sc.take_shared_by_id(product);let n=soulidity_foundation::revenue::balance(catalog::income(&p));test_scenario::return_shared(p);n}
public fun h(n:u8):vector<u8>{vector::tabulate!(32,|_|n)}
public fun layout():Layout{policy::layout(false,0,false,0,1000000,0,vector[])}
public fun scene():Scene{visual::scene(1024,1024,visual::signed(false,0),visual::signed(false,0),0,h(14),b"body",b"pose",vector[b"ref",b"bound",b"free"],vector[visual::track(b"main",0,false)],vector[],vector[visual::anchor(b"root",vector[],visual::signed(false,0),visual::signed(false,0))],vector[])}
public fun representation():Representation{
    let f=visual::fragment(b"image",h(11),b"image/png",1024,1024,1024,0,0,1024,1024,512000,512000,b"main",0,b"root",visual::transform(visual::signed(false,0),visual::signed(false,0),1000000,visual::signed(false,0)),1000000,0,option::none(),option::none(),option::none(),vector[]);
    visual::representation(&scene(),1024,1024,vector[f],vector[])
}
public fun recipe(slots:vector<soulidity_application::output::RecipeSlot>):vector<u8>{let s=scene();output::recipe_hash(&s,&visual::default_colors(&s),slots)}
public fun def(part:vector<u8>,rights:u8,supply:u64):Definition {
    policy::definition(part,b"item",b"style",rights,h(11),h(12),representation(),supply,layout(),policy::bounds(10,10,500000,2000000,90000,vector[vector[255,0,0,255]]),vector[],vector[],true)
}
public fun pack_def(part:vector<u8>,rights:u8,supply:u64):Definition {
    policy::definition(part,b"item",b"pack-style",rights,h(11),h(12),representation(),supply,layout(),policy::bounds(10,10,500000,2000000,90000,vector[vector[255,0,0,255]]),vector[],vector[],true)
}
public fun setup(access_price:u64,completion_mode:u8,completion_price:u64,quota:u64,cap:u64,fixed_fee:u64):Scenario {
    setup_with_output(access_price,completion_mode,completion_price,quota,cap,fixed_fee,false,true,vector[])
}
public fun setup_with_output(access_price:u64,completion_mode:u8,completion_price:u64,quota:u64,cap:u64,fixed_fee:u64,protected:bool,all_packs:bool,allowed_packs:vector<vector<u8>>):Scenario {
    let mut sc=test_scenario::begin(@0xa);
    storage_fixture::initialize(&mut sc);
    kind_registry::init_for_testing(sc.ctx());economics::init_for_testing(sc.ctx());
    sc.next_tx(@0xa);
    let auth:Authority=sc.take_from_sender();
    let cfg=soulidity_v1::native_binding::create_enabled_for_testing<USD>(&auth,1000,500,fixed_fee,@0xf,sc.ctx());
    sc.return_to_sender(auth);sc.next_tx(@0xa);
    let config:Config<USD> = sc.take_shared_by_id(cfg);
    catalog::create_maker(&config,500,sc.ctx());test_scenario::return_shared(config);
    sc.next_tx(@0xa);
    let mut p:Product<USD> = sc.take_shared();let mut c:Control=sc.take_from_sender();
    let registry:KindRegistry=sc.take_shared();let output=default_output(&registry,protected,all_packs,allowed_packs);
    catalog::publish(&mut p,&mut c,0,catalog::with_outputs(catalog::version(h(1),h(2),if(access_price>0)1 else 0,access_price,completion_mode,completion_price,quota,cap,1000,@0xd,soulidity_application::resale::rates(500,500),vector[b"ref",b"bound",b"free"],vector[b"free"],vector[def(b"ref",0,10),def(b"bound",1,10),def(b"free",2,10)],vector[],scene()),vector[output]));test_scenario::return_shared(registry);
    test_scenario::return_shared(p);sc.return_to_sender(c);sc.next_tx(@0xb);sc
}
public fun mint(sc:&mut Scenario,attempt:u8,payment:u64):ID {
    let mut system=prepare_storage(sc);
    let mut p:Product<USD> = sc.take_shared();let mut cfg:Config<USD> = sc.take_shared();
    let clock=clock::create_for_testing(sc.ctx());
    let coin=coin::mint_for_testing<USD>(payment,sc.ctx());
    let intent=default_intent(&p,attempt,default_recipe(&p),sc.sender());
    let mut b=issuer::begin(soulidity_v1::native_binding::application_binding(&cfg),&mut p,&mut cfg,intent,b"default",0,1000,coin,&clock,sc.ctx());
    issuer::select(&mut b,&mut p,policy::definition_hash(&def(b"ref",0,10)),b"ref",layout(),sc.ctx());
    issuer::select(&mut b,&mut p,policy::definition_hash(&def(b"bound",1,10)),b"bound",layout(),sc.ctx());
    issuer::select(&mut b,&mut p,policy::definition_hash(&def(b"free",2,10)),b"free",layout(),sc.ctx());
    let id=finish(sc,b,&mut system,&clock);storage_fixture::return_system(system);
    clock::destroy_for_testing(clock);test_scenario::return_shared(p);test_scenario::return_shared(cfg);id
}

public fun default_output(registry:&KindRegistry,protected:bool,all_packs:bool,allowed_packs:vector<vector<u8>>):Policy {
    output::policy(b"default",protected,if(protected)b"complete/png" else vector[],h(14),all_packs,allowed_packs,vector[
        output::initial_rule(registry,0,document::soul_doc_name(),3,0),
        output::initial_rule(registry,1,document::memory_name(),3,0),
        output::initial_rule(registry,2,string::utf8(b"default"),3,0),
    ])
}
public fun default_recipe(p:&Product<USD>):vector<u8> {
    recipe(vector[
        output::slot(b"ref",option::some(output::selection(catalog::preview_source(p,1,policy::definition_hash(&def(b"ref",0,10))),layout(),option::none()))),
        output::slot(b"bound",option::some(output::selection(catalog::preview_source(p,1,policy::definition_hash(&def(b"bound",1,10))),layout(),option::none()))),
        output::slot(b"free",option::some(output::selection(catalog::preview_source(p,1,policy::definition_hash(&def(b"free",2,10))),layout(),option::none()))),
    ])
}
public fun default_intent(p:&Product<USD>,attempt:u8,recipe:vector<u8>,actor:address):Intent {
    let v=catalog::published(p,1);let policy=catalog::output_policy(v,b"default");
    output::intent(catalog::protocol(p),object::id(p),1,catalog::policy_hash(v),output::policy_hash(&policy),actor,h(attempt),string::utf8(b"OC"),recipe,vector::tabulate!(16,|_|attempt))
}
public fun prepare_storage(sc:&mut Scenario):System {
    sc.take_shared<System>()
}
public fun finish(sc:&mut Scenario,mut build:Build,system:&mut System,clock:&Clock):ID {
    let registry:KindRegistry=sc.take_shared();let rules=output::initials(issuer::output_policy(&build));
    rules.do_ref!(|r|{let kind=output::rule_kind(r);let blob=storage_fixture::blob(system,(100+kind) as u256,false,true,sc.ctx());
        issuer::append_initial_content(&mut build,&registry,kind,output::rule_name(r),blob,system,h((50+kind) as u8),b"encrypted-envelope",clock,sc.ctx());
    });test_scenario::return_shared(registry);
    let blob=storage_fixture::blob(system,200,false,true,sc.ctx());let envelope=if(output::protected(issuer::output_policy(&build)))b"encrypted-render-envelope" else vector[];
    issuer::finish(build,blob,system,h(60),envelope,sc.ctx())
}
