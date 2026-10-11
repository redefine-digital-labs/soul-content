#[test_only]
module soulidity_content::fixtures;
public fun h(n:u8):vector<u8>{vector::tabulate!(32,|_|n)}
