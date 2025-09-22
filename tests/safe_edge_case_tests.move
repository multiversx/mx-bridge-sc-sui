#[test_only]
module bridge_safe::safe_edge_case_tests;

use bridge_safe::pausable;
use bridge_safe::safe::{Self, BridgeSafe};
use locked_token::bridge_token::{Self as br, BRIDGE_TOKEN};
use locked_token::treasury::{Self as lkt, Treasury, FromCoinCap};
use sui::clock;
use sui::coin;
use sui::test_scenario::{Self as ts, Scenario};

public struct TEST_COIN has drop {}
public struct ANOTHER_COIN has drop {}

const ADMIN: address = @0xa11ce;
const USER: address = @0xb0b;
const BRIDGE: address = @0xc0de;

const MIN_AMOUNT: u64 = 100;
const MAX_AMOUNT: u64 = 1000000;

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

    s
}

#[test]
fun test_set_batch_size_boundary_values() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Test minimum valid batch size (1)
        safe::set_batch_size(&mut safe, 1, ts::ctx(&mut scenario));
        assert!(safe::get_batch_size(&safe) == 1, 0);

        // Test maximum valid batch size (100)
        safe::set_batch_size(&mut safe, 100, ts::ctx(&mut scenario));
        assert!(safe::get_batch_size(&safe) == 100, 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_batch_timeout_edge_cases() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Test setting batch timeout to 0 (should be allowed)
        safe::set_batch_timeout_ms(&mut safe, 0, ts::ctx(&mut scenario));
        assert!(safe::get_batch_timeout_ms(&safe) == 0, 0);

        // Test setting batch timeout equal to settle timeout (should be allowed)
        let settle_timeout = safe::get_batch_settle_timeout_ms(&safe);
        safe::set_batch_timeout_ms(&mut safe, settle_timeout, ts::ctx(&mut scenario));
        assert!(safe::get_batch_timeout_ms(&safe) == settle_timeout, 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_multiple_token_whitelist() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist first token
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        // Whitelist second token
        safe::whitelist_token<ANOTHER_COIN>(
            &mut safe,
            MIN_AMOUNT * 2,
            MAX_AMOUNT * 2,
            false, // not native
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        // Verify both tokens are whitelisted
        assert!(safe::is_token_whitelisted<TEST_COIN>(&safe), 0);
        assert!(safe::is_token_whitelisted<ANOTHER_COIN>(&safe), 1);

        // Verify different limits
        assert!(safe::get_token_min_limit<TEST_COIN>(&safe) == MIN_AMOUNT, 2);
        assert!(safe::get_token_min_limit<ANOTHER_COIN>(&safe) == MIN_AMOUNT * 2, 3);
        assert!(safe::get_token_max_limit<TEST_COIN>(&safe) == MAX_AMOUNT, 4);
        assert!(safe::get_token_max_limit<ANOTHER_COIN>(&safe) == MAX_AMOUNT * 2, 5);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_token_limit_updates() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist token
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        // Update min limit to 0
        safe::set_token_min_limit<TEST_COIN>(&mut safe, 1, ts::ctx(&mut scenario));
        assert!(safe::get_token_min_limit<TEST_COIN>(&safe) == 1, 0);

        // Update max limit to maximum u64
        let max_u64 = 18446744073709551615u64;
        safe::set_token_max_limit<TEST_COIN>(
            &mut safe,
            max_u64,
            ts::ctx(&mut scenario),
        );
        assert!(safe::get_token_max_limit<TEST_COIN>(&safe) == max_u64, 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_bridge_address_updates() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        assert!(safe::get_bridge_addr(&safe) == ADMIN, 0);

        safe::set_bridge_addr(&mut safe, BRIDGE, ts::ctx(&mut scenario));
        assert!(safe::get_bridge_addr(&safe) == BRIDGE, 1);

        let new_bridge = @0xbeef;
        safe::set_bridge_addr(&mut safe, new_bridge, ts::ctx(&mut scenario));
        assert!(safe::get_bridge_addr(&safe) == new_bridge, 2);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_init_supply_zero_amount() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let zero_coin = coin::mint_for_testing<TEST_COIN>(0, ts::ctx(&mut scenario));

        safe::init_supply<TEST_COIN>(
            &mut safe,
            zero_coin,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 0, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test init_supply with non-native token (should fail)
#[test]
#[expected_failure(abort_code = safe::EInsufficientBalance)]
fun test_init_supply_non_native_token() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist token as NON-native
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));

        safe::init_supply<TEST_COIN>(
            &mut safe,
            coin,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::ETokenNotWhitelisted)]
fun test_init_supply_removed_token() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist token as native
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        // Remove token from whitelist
        safe::remove_token_from_whitelist<TEST_COIN>(&mut safe, ts::ctx(&mut scenario));

        let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));

        // This should fail because token is no longer whitelisted
        safe::init_supply<TEST_COIN>(
            &mut safe,
            coin,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test pause/unpause sequence
#[test]
fun test_pause_unpause_sequence() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        let pause = safe::get_pause(&safe);
        assert!(!pausable::is_paused(pause), 0);

        // Pause
        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));
        let pause = safe::get_pause(&safe);
        assert!(pausable::is_paused(pause), 1);

        // Unpause
        safe::unpause_contract(&mut safe, ts::ctx(&mut scenario));
        let pause = safe::get_pause(&safe);
        assert!(!pausable::is_paused(pause), 2);

        // Pause again
        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));
        let pause = safe::get_pause(&safe);
        assert!(pausable::is_paused(pause), 3);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test complex batch timeout scenarios
#[test]
fun test_complex_batch_timeout_scenarios() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Set very short timeouts for testing
        safe::set_batch_timeout_ms(&mut safe, 1000, ts::ctx(&mut scenario)); // 1 second

        // Create multiple batches with different timestamps
        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));

        // Advance time slightly
        clock::increment_for_testing(&mut clock, 500);
        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));

        // Advance time more
        clock::increment_for_testing(&mut clock, 1000);
        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));

        // Should have 3 batches
        assert!(safe::get_batches_count(&safe) == 3, 0);

        // Test that we can retrieve all batches
        let (batch1, _is_final1) = safe::get_batch(&safe, 1, &clock);
        let (batch2, _is_final2) = safe::get_batch(&safe, 2, &clock);
        let (batch3, _is_final3) = safe::get_batch(&safe, 3, &clock);

        assert!(safe::get_batch_nonce(&batch1) == 1, 1);
        assert!(safe::get_batch_nonce(&batch2) == 2, 2);
        assert!(safe::get_batch_nonce(&batch3) == 3, 3);

        // Check finality based on time
        // Note: The exact finality depends on the settle timeout and when batches were created

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test that admin functions fail with wrong admin
#[test]
#[expected_failure(abort_code = 0)]
fun test_set_batch_size_wrong_admin() {
    let mut scenario = setup();

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // USER tries to set batch size but is not admin
        safe::set_batch_size(&mut safe,  50, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test get_stored_coin_balance for non-initialized token
#[test]
fun test_get_stored_coin_balance_non_initialized() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Token not initialized, should return 0
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 0, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test batch settle timeout validation when contract is not paused
#[test]
#[expected_failure(abort_code = 1)]
fun test_set_batch_settle_timeout_not_paused() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Don't pause the contract - this should fail
        safe::set_batch_settle_timeout_ms(
            &mut safe,
            7200000,
            &clock,
            ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}
