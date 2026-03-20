#[test_only]
module bridge_safe::audit_fixes_tests;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::safe::{Self, BridgeSafe};
use sui::test_scenario::{Self as ts, Scenario};

public struct TEST_COIN has drop {}

const ADMIN: address = @0xa11ce;

const INITIAL_QUORUM: u64 = 3;
const MIN_AMOUNT: u64 = 100;
const MAX_AMOUNT: u64 = 1_000_000;

const PK1: vector<u8> = b"12345678901234567890123456789012";
const PK2: vector<u8> = b"abcdefghijklmnopqrstuvwxyz123456";
const PK3: vector<u8> = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";

fun setup(): Scenario {
    let mut s = ts::begin(ADMIN);

    s.next_tx(ADMIN);
    {
        safe::init_for_testing(s.ctx());
    };

    s
}

fun setup_with_bridge(): Scenario {
    let mut s = setup();

    s.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&s);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&s);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
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

// === Quorum > relayer count on initialization ===

#[test]
#[expected_failure(abort_code = bridge::EQuorumExceedsRelayers)]
fun test_initialize_quorum_exceeds_relayers() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        let public_keys = vector[PK1, PK2, PK3];

        // Quorum of 4 but only 3 relayers - should fail
        bridge::initialize(
            public_keys,
            4,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_initialize_quorum_equals_relayers() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        let public_keys = vector[PK1, PK2, PK3];

        // Quorum of 3 with 3 relayers - should succeed
        bridge::initialize(
            public_keys,
            3,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let bridge = ts::take_shared<Bridge>(&scenario);
        assert!(bridge::get_quorum(&bridge) == 3, 0);
        assert!(bridge::get_relayer_count(&bridge) == 3, 1);
        ts::return_shared(bridge);
    };

    ts::end(scenario);
}

// === Direct de-whitelisting of mint-burn token ===

#[test]
#[expected_failure(abort_code = safe::EIncompatibleTokenFlags)]
fun test_remove_mint_burn_token_via_safe_fails() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist as native first
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            ts::ctx(&mut scenario),
        );

        // Change to non-native, then set mint-burn
        safe::set_token_is_native<TEST_COIN>(&mut safe, false, ts::ctx(&mut scenario));
        safe::set_token_is_mint_burn<TEST_COIN>(&mut safe, true, ts::ctx(&mut scenario));

        // Try to remove via safe directly - should fail because it's mint-burn
        safe::remove_token_from_whitelist<TEST_COIN>(&mut safe, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_remove_native_token_via_safe_succeeds() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist as native
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            ts::ctx(&mut scenario),
        );

        assert!(safe::is_token_whitelisted<TEST_COIN>(&safe), 0);

        // Remove via safe directly - should succeed because it's native
        safe::remove_token_from_whitelist<TEST_COIN>(&mut safe, ts::ctx(&mut scenario));

        assert!(!safe::is_token_whitelisted<TEST_COIN>(&safe), 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// === Events for config updates (verify no aborts) ===

#[test]
fun test_config_update_events_emitted() {
    let mut scenario = setup_with_bridge();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let clock = sui::clock::create_for_testing(ts::ctx(&mut scenario));

        // All of these should succeed and emit events
        safe::set_batch_timeout_ms(&mut safe, 3000, ts::ctx(&mut scenario));
        assert!(safe::get_batch_timeout_ms(&safe) == 3000, 0);

        safe::set_batch_size(&mut safe, 20, ts::ctx(&mut scenario));
        assert!(safe::get_batch_size(&safe) == 20, 1);

        // Pause to update settle timeouts
        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));
        bridge::pause_contract(&mut bridge, &safe, ts::ctx(&mut scenario));

        safe::set_batch_settle_timeout_ms(&mut safe, 20000, &clock, ts::ctx(&mut scenario));
        assert!(safe::get_batch_settle_timeout_ms(&safe) == 20000, 2);

        bridge::set_batch_settle_timeout_ms(
            &mut bridge,
            &safe,
            20000,
            &clock,
            ts::ctx(&mut scenario),
        );
        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == 20000, 3);

        sui::clock::destroy_for_testing(clock);
        ts::return_shared(bridge);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}
