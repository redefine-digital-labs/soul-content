#[test_only]
module soulidity_standard::foreign;
public struct Value has key, store { id: UID }
public fun new(ctx: &mut TxContext): Value { Value { id: object::new(ctx) } }
