#[test_only]
module bridge_safe::security_tests;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::roles::{AdminCap, BridgeCap};
use bridge_safe::safe::{Self, BridgeSafe, EAmountAboveMaximum, EAmountBelowMinimum};
use sui::clock;
use sui::coin;
use sui::test_scenario as ts;

public struct TEST_COIN has drop {}

const ADMIN: address = @0xa11ce;
const USER: address = @0xb0b;
const ATTACKER: address = @0xabad1dea;
const RECIPIENT_VECTOR: vector<u8> = b"12345678901234567890123456789012";

const RELAYER1: address = @0xb0b;
const RELAYER2: address = @0xc0de;
const RELAYER3: address = @0xd00d;

const MIN_AMOUNT: u64 = 100;
const MAX_AMOUNT: u64 = 1_000_000;
const DEPOSIT_AMOUNT: u64 = 50_000;
const DRAIN_AMOUNT: u64 = 10_000;

const INITIAL_QUORUM: u64 = 3;

const PK1: vector<u8> = b"12345678901234567890123456789012";
const PK2: vector<u8> = b"abcdefghijklmnopqrstuvwxyz123456";
const PK3: vector<u8> = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";

#[test]
#[expected_failure(abort_code = bridge::ESettleTimeoutBelowSafeBatch)]
fun test_bridge_settle_timeout_can_be_set_below_safe_batch_timeout() {
    let mut scenario = ts::begin(ADMIN);

    ts::next_tx(&mut scenario, ADMIN);
    {
        safe::init_for_testing(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            &admin_cap,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let safe_addr = object::id_address(&safe);
        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            safe_addr,
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let safe_batch_timeout = safe::get_batch_timeout_ms(&safe);
        assert!(safe_batch_timeout == 5000, 0);

        bridge::pause_contract(&mut bridge, &admin_cap, ts::ctx(&mut scenario));

        let new_settle = 1000;
        bridge::set_batch_settle_timeout_ms(
            &mut bridge,
            &admin_cap,
            &safe,
            new_settle,
            &clock,
            ts::ctx(&mut scenario),
        );

        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == new_settle, 1);

        ts::return_shared(bridge);
        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

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

#[test]
#[expected_failure(abort_code = bridge::EDepositAlreadyExecuted)]
fun test_replay_allows_double_spend_with_same_deposit_nonce() {
    let mut scenario = ts::begin(ADMIN);

    ts::next_tx(&mut scenario, ADMIN);
    {
        safe::init_for_testing(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            &admin_cap,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let safe_addr = object::id_address(&safe);
        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            safe_addr,
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let coin_in = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
        safe::deposit<TEST_COIN>(
            &mut safe,
            coin_in,
            b"12345678901234567890123456789012",
            &clock,
            ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };

    // RELAYER executes the same deposit nonce twice with is_batch_complete=false
    ts::next_tx(&mut scenario, RELAYER1);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        bridge::execute_transfer_for_testing<TEST_COIN>(
            &mut bridge,
            &mut safe,
            vector[USER],
            vector[DRAIN_AMOUNT],
            vector[1], // deposit nonce 1 used twice
            1, // batch nonce
            false, // is_batch_complete=false so replay remains possible
            &clock,
            ts::ctx(&mut scenario),
        );

        bridge::execute_transfer_for_testing<TEST_COIN>(
            //should abort here
            &mut bridge,
            &mut safe,
            vector[USER],
            vector[DRAIN_AMOUNT],
            vector[1],
            1,
            false,
            &clock,
            ts::ctx(&mut scenario),
        );

        // Balance should be reduced by twice the drain amount ( if not fixed )
        assert!(
            safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == (DEPOSIT_AMOUNT - 2 * DRAIN_AMOUNT),
            0,
        );

        ts::return_shared(bridge);
        ts::return_shared(safe);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EInvalidTokenLimits)]
fun test_set_min_above_max_is_allowed_vulnerable() {
    let mut scenario = ts::begin(ADMIN);
    {
        safe::init_for_testing(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            &admin_cap,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let invalid_min = MAX_AMOUNT + 1;
        safe::set_token_min_limit<TEST_COIN>(
            &mut safe,
            &admin_cap,
            invalid_min,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_token_min_limit<TEST_COIN>(&safe) == invalid_min, 0);

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::end(scenario);
}
