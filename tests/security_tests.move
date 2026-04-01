#[test_only]
module bridge_safe::security_tests;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::bridge_roles::{Self as bridge_roles, BridgeCap};
use bridge_safe::safe::{Self, BridgeSafe};
use locked_token::bridge_token::{Self as br, BRIDGE_TOKEN};
use locked_token::treasury::{Self as lkt, Treasury, FromCoinCap};
use sui::clock;
use sui::coin;
use sui::test_scenario::{Self as ts, Scenario};

public struct TEST_COIN has drop {}

const ADMIN: address = @0xa11ce;
const USER: address = @0xb0b;

const MIN_AMOUNT: u64 = 100;
const MAX_AMOUNT: u64 = 1_000_000;
const DEPOSIT_AMOUNT: u64 = 50_000;
const DRAIN_AMOUNT: u64 = 10_000;

const INITIAL_QUORUM: u64 = 3;

const PK1: vector<u8> = b"12345678901234567890123456789012";
const PK2: vector<u8> = b"abcdefghijklmnopqrstuvwxyz123456";
const PK3: vector<u8> = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";

fun setup(): Scenario {
    let mut s = ts::begin(ADMIN);

    br::init_for_testing(s.ctx());

    s.next_tx(ADMIN);
    {
        let mut treasury = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        lkt::transfer_to_coin_cap<BRIDGE_TOKEN>(&mut treasury, ADMIN, s.ctx());
        lkt::transfer_from_coin_cap<BRIDGE_TOKEN>(&mut treasury, ADMIN, s.ctx());
        ts::return_shared(treasury);
    };

    s.next_tx(ADMIN);
    {
        let from_cap_db = s.take_from_address<FromCoinCap<BRIDGE_TOKEN>>(ADMIN);
        safe::init_for_testing(from_cap_db, s.ctx());
    };

    s.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&s);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&s);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false,
            ts::ctx(&mut s),
        );

        let safe_addr = object::id_address(&safe);
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            safe_addr,
            bridge_cap,
            ts::ctx(&mut s),
        );

        ts::return_shared(safe);
    };

    s
}

#[test]
#[expected_failure(abort_code = bridge::ESettleTimeoutBelowSafeBatch)]
fun test_bridge_settle_timeout_can_be_set_below_safe_batch_timeout() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let safe_batch_timeout = safe::get_batch_timeout_ms(&safe);
        assert!(safe_batch_timeout == 5000, 0);

        bridge::pause_contract(&mut bridge, &safe, ts::ctx(&mut scenario));

        let new_settle = 1000;
        bridge::set_batch_settle_timeout_ms(
            &mut bridge,
            &safe,
            new_settle,
            &clock,
            ts::ctx(&mut scenario),
        );

        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == new_settle, 1);

        ts::return_shared(bridge);
        ts::return_shared(safe);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EDepositAlreadyExecuted)]
fun test_replay_allows_double_spend_with_same_deposit_nonce() {
    let mut scenario = setup();

    scenario.next_tx(USER);
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

    // Compute actual relayer address from the first public key
    let pk1 = PK1;
    let relayer1_bytes = sui::hash::blake2b256(&pk1);
    let relayer1 = sui::address::from_bytes(relayer1_bytes);

    // RELAYER executes the same deposit nonce twice in the same transaction
    scenario.next_tx(relayer1);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // First call should succeed
        bridge::execute_transfer_for_testing<TEST_COIN>(
            &mut bridge,
            &mut safe,
            vector[USER],
            vector[DRAIN_AMOUNT],
            1, // batch nonce
            false,
            &mut treasury,
            &clock,
            ts::ctx(&mut scenario),
        );

        // Second call with same deposit nonce should abort
        bridge::execute_transfer_for_testing<TEST_COIN>(
            &mut bridge,
            &mut safe,
            vector[USER],
            vector[DRAIN_AMOUNT],
            1, // same batch nonce
            false,
            &mut treasury,
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
        ts::return_shared(treasury);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
fun test_safe_init_cap_consumed_after_initialize() {
    let mut scenario = ts::begin(ADMIN);

    br::init_for_testing(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut treasury = ts::take_shared<lkt::Treasury<BRIDGE_TOKEN>>(&scenario);
        lkt::transfer_to_coin_cap<BRIDGE_TOKEN>(&mut treasury, ADMIN, scenario.ctx());
        lkt::transfer_from_coin_cap<BRIDGE_TOKEN>(&mut treasury, ADMIN, scenario.ctx());
        ts::return_shared(treasury);
    };

    scenario.next_tx(ADMIN);
    {
        // Simulate module deployment: init() mints SafeInitCap and sends it to the deployer
        safe::trigger_init_for_testing(scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        // Deployer takes the cap from their inventory and calls initialize — exactly the real flow
        let init_cap = ts::take_from_sender<safe::SafeInitCap>(&scenario);
        let from_cap = ts::take_from_sender<FromCoinCap<BRIDGE_TOKEN>>(&scenario);
        safe::initialize(init_cap, from_cap, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        // BridgeSafe was created: exactly one shared object exists
        let safe_obj = ts::take_shared<BridgeSafe>(&scenario);

        // SafeInitCap is gone: it has no address anymore because object::delete was called.
        // Confirm the sender has no SafeInitCap in their inventory.
        assert!(!ts::has_most_recent_for_sender<safe::SafeInitCap>(&scenario), 0);

        ts::return_shared(safe_obj);
    };

    ts::end(scenario);
}

// Regression test: a BridgeCap minted for a different safe must be rejected by safe::transfer.
#[test]
#[expected_failure(abort_code = safe::EUnauthorizedBridgeCap)]
fun test_unauthorized_bridge_cap_rejected() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe_obj = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<lkt::Treasury<BRIDGE_TOKEN>>(&scenario);

        // Simulate an attacker who obtained a BridgeCap bound to a different safe
        let witness = bridge_roles::grant_witness();
        let wrong_safe_id = object::id_from_address(@0xdeadbeef);
        let rogue_cap = bridge_roles::publish_caps(witness, wrong_safe_id, scenario.ctx());

        // Must abort with EUnauthorizedBridgeCap — the safe rejects the foreign cap
        safe::transfer<TEST_COIN>(
            &mut safe_obj,
            &rogue_cap,
            USER,
            DRAIN_AMOUNT,
            &mut treasury,
            scenario.ctx(),
        );

        transfer::public_transfer(rogue_cap, ADMIN); // unreachable
        ts::return_shared(safe_obj);
        ts::return_shared(treasury);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EInvalidTokenLimits)]
fun test_set_min_above_max_is_allowed_vulnerable() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Token is already whitelisted by setup(), so we can directly set limits
        let invalid_min = MAX_AMOUNT + 1;
        safe::set_token_min_limit<TEST_COIN>(
            &mut safe,
            invalid_min,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_token_min_limit<TEST_COIN>(&safe) == invalid_min, 0);

        ts::return_shared(safe);
    };

    ts::end(scenario);
}
