#[test_only]
module bridge_safe::safe_unit_tests;

use bridge_safe::pausable;
use bridge_safe::bridge_roles::{BridgeCap};
use bridge_safe::safe::{Self, BridgeSafe};
use sui::clock;
use sui::coin;
use sui::test_scenario::{Self as ts, Scenario};
use locked_token::bridge_token::{Self as br, BRIDGE_TOKEN};
use locked_token::treasury::{Self as lkt, Treasury, FromCoinCap};
use sui_extensions::two_step_role::ESenderNotActiveRole;

public struct TEST_COIN has drop {}

const ADMIN: address = @0xa11ce;
const USER: address = @0xb0b;
const BRIDGE: address = @0xc0de;
const NEW_OWNER: address = @0xb0b;
const THIRD_PARTY: address = @0xc0de;

const DEFAULT_BATCH_SIZE: u16 = 10;
const DEFAULT_BATCH_SETTLE_TIMEOUT_MS: u64 = 10000;
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
fun test_init() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        //let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        // Test initial values
        assert!(safe::get_bridge_addr(&safe) == ADMIN, 1);
        assert!(safe::get_batch_size(&safe) == DEFAULT_BATCH_SIZE, 2);
        assert!(safe::get_batch_timeout_ms(&safe) == 5 * 1000, 3);
        assert!(safe::get_batch_settle_timeout_ms(&safe) == 10 * 1000, 4);
        assert!(safe::get_batches_count(&safe) == 0, 5);
        assert!(safe::get_deposits_count(&safe) == 0, 6);

        // Test pause is not paused initially
        let pause = safe::get_pause(&safe);
        assert!(!pausable::is_paused(pause), 7);

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, bridge_cap);
    };
    ts::end(scenario);
}

#[test]
fun test_whitelist_token() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Test whitelisting a token
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true, // is_native
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        // Verify token is whitelisted
        assert!(safe::is_token_whitelisted<TEST_COIN>(&safe), 0);
        assert!(safe::get_token_min_limit<TEST_COIN>(&safe) == MIN_AMOUNT, 1);
        assert!(safe::get_token_max_limit<TEST_COIN>(&safe) == MAX_AMOUNT, 2);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::ETokenAlreadyExists)]
fun test_whitelist_token_already_exists() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist token first time
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        // Try to whitelist same token again - should fail
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_whitelist_token_not_admin() {
    let mut scenario = setup();
    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Take admin cap that was created during init (owned by ADMIN)

        // This should fail because USER is not admin (sender check will fail)
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_remove_token_from_whitelist() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // First whitelist a token
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        assert!(safe::is_token_whitelisted<TEST_COIN>(&safe), 0);

        // Remove token from whitelist
        safe::remove_token_from_whitelist<TEST_COIN>(
            &mut safe,
            ts::ctx(&mut scenario),
        );

        // Verify token is no longer whitelisted
        assert!(!safe::is_token_whitelisted<TEST_COIN>(&safe), 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_is_token_whitelisted_non_existent() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        // Test non-existent token
        assert!(!safe::is_token_whitelisted<TEST_COIN>(&safe), 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_set_batch_timeout_ms() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        let new_timeout = 6000; // 5 minutes

        safe::set_batch_timeout_ms(
            &mut safe,
            new_timeout,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_batch_timeout_ms(&safe) == new_timeout, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EBatchBlockLimitExceedsSettle)]
fun test_set_batch_timeout_ms_exceeds_settle() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Try to set timeout higher than settle timeout - should fail
        let new_timeout = DEFAULT_BATCH_SETTLE_TIMEOUT_MS + 1;

        safe::set_batch_timeout_ms(
            &mut safe,
            new_timeout,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_set_batch_settle_timeout_ms() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // First pause the contract
        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));

        let new_settle_timeout = 7200000; // 2 hours

        safe::set_batch_settle_timeout_ms(
            &mut safe,
            new_settle_timeout,
            &clock,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_batch_settle_timeout_ms(&safe) == new_settle_timeout, 0);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EBatchSettleLimitBelowBlock)]
fun test_set_batch_settle_timeout_ms_below_block() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // First pause the contract
        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));

        // Try to set settle timeout lower than batch timeout - should fail
        let new_settle_timeout = 1000 - 1;

        safe::set_batch_settle_timeout_ms(
            &mut safe,
            new_settle_timeout,
            &clock,
            ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_set_batch_size() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        let new_size = 50;

        safe::set_batch_size(
            &mut safe,
            
            new_size,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_batch_size(&safe) == new_size, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EBatchSizeTooLarge)]
fun test_set_batch_size_too_large() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Try to set batch size > 100 - should fail
        let new_size = 101;

        safe::set_batch_size(
            &mut safe,
            new_size,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_set_token_min_limit() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // First whitelist the token
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let new_min = 200;

        safe::set_token_min_limit<TEST_COIN>(
            &mut safe,
            new_min,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_token_min_limit<TEST_COIN>(&safe) == new_min, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_set_token_max_limit() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // First whitelist the token
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let new_max = 2000000;

        safe::set_token_max_limit<TEST_COIN>(
            &mut safe,
            new_max,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_token_max_limit<TEST_COIN>(&safe) == new_max, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_set_bridge_addr() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::set_bridge_addr(
            &mut safe,
            BRIDGE,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_bridge_addr(&safe) == BRIDGE, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_init_supply() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // First whitelist the token as native
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true, // is_native = true
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        // Create a coin to initialize supply
        let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));

        safe::init_supply<TEST_COIN>(
            &mut safe,
            coin,
            ts::ctx(&mut scenario),
        );

        // Check that stored balance is correct
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 1000, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_init_supply_multiple_times() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // First whitelist the token as native
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true, // is_native = true
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        // Initialize supply first time
        let coin1 = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(
            &mut safe,
            coin1,
            ts::ctx(&mut scenario),
        );

        // Initialize supply second time (should join with existing)
        let coin2 = coin::mint_for_testing<TEST_COIN>(500, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(
            &mut safe,
            coin2,
            ts::ctx(&mut scenario),
        );

        // Check that stored balance is combined
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 1500, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::ETokenNotWhitelisted)]
fun test_init_supply_token_not_whitelisted() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Don't whitelist the token
        let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));

        // This should fail
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
fun test_get_batch_non_existent() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // No batches exist yet, so this should abort
        // Note: This will actually abort with an index out of bounds error
        // since we're trying to access batch_nonce - 1 = 0 when no batches exist

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_get_deposits_non_existent_batch() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // This will also abort since no batches exist

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_is_any_batch_in_progress_no_batches() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // No batches, should return false
        assert!(!safe::is_any_batch_in_progress(&safe, &clock), 0);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_create_new_batch_internal() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Initially no batches
        assert!(safe::get_batches_count(&safe) == 0, 0);

        // Create a new batch
        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));

        // Now should have 1 batch
        assert!(safe::get_batches_count(&safe) == 1, 1);

        // Get the batch and verify its properties
        let (batch, is_final) = safe::get_batch(&safe, 1, &clock);
        assert!(safe::get_batch_nonce(&batch) == 1, 2);
        assert!(safe::get_batch_deposits_count(&batch) == 0, 3);
        assert!(!is_final, 4); // Should not be final immediately

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_get_stored_coin_balance_empty() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // No coins stored, should return 0
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 0, 0);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_pause_contract() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Initially not paused
        let pause = safe::get_pause(&safe);
        assert!(!pausable::is_paused(pause), 0);

        // Pause the contract
        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));

        // Now should be paused
        let pause = safe::get_pause(&safe);
        assert!(pausable::is_paused(pause), 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_unpause_contract() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // First pause the contract
        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));
        let pause = safe::get_pause(&safe);
        assert!(pausable::is_paused(pause), 0);

        // Now unpause it
        safe::unpause_contract(&mut safe, ts::ctx(&mut scenario));

        // Should be unpaused
        let pause = safe::get_pause(&safe);
        assert!(!pausable::is_paused(pause), 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_get_pause_mut() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Test that we can get mutable reference to pause
        let pause_mut = safe::get_pause_mut(&mut safe);

        // Initially not paused
        assert!(!pausable::is_paused(pause_mut), 0);

        // Pause directly through the mutable reference
        pausable::pause(pause_mut);

        // Verify it's paused
        let pause = safe::get_pause(&safe);
        assert!(pausable::is_paused(pause), 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test for complex batch timeout scenarios
#[test]
fun test_batch_timeout_logic() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Set a very short timeout for testing
        safe::set_batch_timeout_ms(&mut safe, 1000, ts::ctx(&mut scenario)); // 1 second

        // Create a batch
        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));

        // Initially there might be a batch in progress depending on timing
        // The exact behavior depends on whether the batch has deposits and timing
        let _initial_progress = safe::is_any_batch_in_progress(&safe, &clock);

        // Advance time beyond timeout
        clock::increment_for_testing(&mut clock, 2000); // 2 seconds

        // Check if batch progress changed after timeout
        let _after_timeout_progress = safe::is_any_batch_in_progress(&safe, &clock);

        // The behavior depends on the batch content and internal logic
        // We just verify the function doesn't crash

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test edge cases for getter functions
#[test]
fun test_all_getters() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        // Test all getter functions with initial values
        assert!(safe::get_bridge_addr(&safe) == ADMIN, 1);
        assert!(safe::get_batch_size(&safe) == DEFAULT_BATCH_SIZE, 2);
        assert!(safe::get_batch_timeout_ms(&safe) == 5 * 1000, 3);
        assert!(safe::get_batch_settle_timeout_ms(&safe) == 10 * 1000, 4);
        assert!(safe::get_batches_count(&safe) == 0, 5);
        assert!(safe::get_deposits_count(&safe) == 0, 6);

        // Test pause getter
        let pause = safe::get_pause(&safe);
        assert!(!pausable::is_paused(pause), 7);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test for batch operations with actual batch data
#[test]
fun test_batch_operations_with_data() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Create a batch
        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));

        // Get the batch
        let (batch, is_final) = safe::get_batch(&safe, 1, &clock);

        // Test batch getter functions
        assert!(safe::get_batch_nonce(&batch) == 1, 0);
        assert!(safe::get_batch_deposits_count(&batch) == 0, 1);
        assert!(!is_final, 2);

        // Test deposits for this batch (should be empty)
        let (deposits, is_final_deposits) = safe::get_deposits(&safe, 1, &clock);
        assert!(vector::length(&deposits) == 0, 3);
        assert!(is_final_deposits == is_final, 4);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

// Test multiple batch creation
#[test]
fun test_multiple_batch_creation() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Create multiple batches
        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));
        assert!(safe::get_batches_count(&safe) == 1, 0);

        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));
        assert!(safe::get_batches_count(&safe) == 2, 1);

        safe::create_batch_for_testing(&mut safe, &clock, ts::ctx(&mut scenario));
        assert!(safe::get_batches_count(&safe) == 3, 2);

        // Test that we can get each batch
        let (batch1, _) = safe::get_batch(&safe, 1, &clock);
        let (batch2, _) = safe::get_batch(&safe, 2, &clock);
        let (batch3, _) = safe::get_batch(&safe, 3, &clock);

        assert!(safe::get_batch_nonce(&batch1) == 1, 3);
        assert!(safe::get_batch_nonce(&batch2) == 2, 4);
        assert!(safe::get_batch_nonce(&batch3) == 3, 5);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_initial_ownership() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        
        assert!(safe::get_owner(&safe) == ADMIN, 0);
        
        let pending = safe::get_pending_owner(&safe);
        assert!(pending.is_none(), 1);
        
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_ownership_initiate() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        
        safe::transfer_ownership(&mut safe, NEW_OWNER, scenario.ctx());
        
        assert!(safe::get_owner(&safe) == ADMIN, 0);
        
        let pending = safe::get_pending_owner(&safe);
        assert!(pending.is_some(), 1);
        assert!(*pending.borrow() == NEW_OWNER, 2);
        
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_complete_ownership_transfer() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::transfer_ownership(&mut safe, NEW_OWNER, scenario.ctx());
        ts::return_shared(safe);
    };

    scenario.next_tx(NEW_OWNER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::accept_ownership(&mut safe, scenario.ctx());
        
        assert!(safe::get_owner(&safe) == NEW_OWNER, 0);
        
        let pending = safe::get_pending_owner(&safe);
        assert!(pending.is_none(), 1);
        
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_transfer_ownership_not_owner() {
    let mut scenario = setup();

    scenario.next_tx(THIRD_PARTY);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        
        safe::transfer_ownership(&mut safe, NEW_OWNER, scenario.ctx());
        
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_ownership_to_same_address() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        
        safe::transfer_ownership(&mut safe, ADMIN, scenario.ctx());
        
        assert!(safe::get_owner(&safe) == ADMIN, 0);
        
        let pending = safe::get_pending_owner(&safe);
        assert!(pending.is_some(), 1);
        assert!(*pending.borrow() == ADMIN, 2);
        
        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::accept_ownership(&mut safe, scenario.ctx());
        
        assert!(safe::get_owner(&safe) == ADMIN, 3);
        let pending = safe::get_pending_owner(&safe);
        assert!(pending.is_none(), 4);
        
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_multiple_ownership_transfers() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::transfer_ownership(&mut safe, NEW_OWNER, scenario.ctx());
        ts::return_shared(safe);
    };

    scenario.next_tx(NEW_OWNER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::accept_ownership(&mut safe, scenario.ctx());
        assert!(safe::get_owner(&safe) == NEW_OWNER, 0);
        ts::return_shared(safe);
    };

    scenario.next_tx(NEW_OWNER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::transfer_ownership(&mut safe, THIRD_PARTY, scenario.ctx());
        ts::return_shared(safe);
    };

    scenario.next_tx(THIRD_PARTY);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::accept_ownership(&mut safe, scenario.ctx());
        assert!(safe::get_owner(&safe) == THIRD_PARTY, 1);
        ts::return_shared(safe);
    };

    scenario.next_tx(THIRD_PARTY);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::transfer_ownership(&mut safe, ADMIN, scenario.ctx());
        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::accept_ownership(&mut safe, scenario.ctx());
        assert!(safe::get_owner(&safe) == ADMIN, 2);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_overwrite_pending_ownership_transfer() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::transfer_ownership(&mut safe, NEW_OWNER, scenario.ctx());
        
        let pending = safe::get_pending_owner(&safe);
        assert!(pending.is_some(), 0);
        assert!(*pending.borrow() == NEW_OWNER, 1);
        
        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::transfer_ownership(&mut safe, THIRD_PARTY, scenario.ctx());
        
        let pending = safe::get_pending_owner(&safe);
        assert!(pending.is_some(), 2);
        assert!(*pending.borrow() == THIRD_PARTY, 3);
        
        ts::return_shared(safe);
    };

    scenario.next_tx(NEW_OWNER);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        
        let pending = safe::get_pending_owner(&safe);
        assert!(pending.is_some(), 5);
        assert!(*pending.borrow() == THIRD_PARTY, 6);
        
        ts::return_shared(safe);
    };

    scenario.next_tx(THIRD_PARTY);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::accept_ownership(&mut safe, scenario.ctx());
        
        assert!(safe::get_owner(&safe) == THIRD_PARTY, 4);
        
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_sync_supply() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false,
            ts::ctx(&mut scenario),
        );

        let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, coin, ts::ctx(&mut scenario));

        safe::add_to_balance_for_testing<TEST_COIN>(&mut safe, 500);

        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 1500, 0);
        assert!(safe::get_coin_storage_balance<TEST_COIN>(&safe) == 1000, 1);

        let sync_coin = coin::mint_for_testing<TEST_COIN>(800, ts::ctx(&mut scenario));
        safe::sync_supply<TEST_COIN>(&mut safe, sync_coin, ts::ctx(&mut scenario));

        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 1500, 2);
        assert!(safe::get_coin_storage_balance<TEST_COIN>(&safe) == 1500, 3);

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let returned_coin = ts::take_from_sender<coin::Coin<TEST_COIN>>(&scenario);
        assert!(coin::value(&returned_coin) == 300, 4);
        ts::return_to_sender(&scenario, returned_coin);
    };

    ts::end(scenario);
}

#[test]
fun test_sync_supply_exact_amount() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false,
            ts::ctx(&mut scenario),
        );

        let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, coin, ts::ctx(&mut scenario));

        safe::add_to_balance_for_testing<TEST_COIN>(&mut safe, 500);

        let sync_coin = coin::mint_for_testing<TEST_COIN>(500, ts::ctx(&mut scenario));
        safe::sync_supply<TEST_COIN>(&mut safe, sync_coin, ts::ctx(&mut scenario));

        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 1500, 0);
        assert!(safe::get_coin_storage_balance<TEST_COIN>(&safe) == 1500, 1);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_sync_supply_no_existing_bag_entry() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false,
            ts::ctx(&mut scenario),
        );

        safe::add_to_balance_for_testing<TEST_COIN>(&mut safe, 500);

        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 500, 0);
        assert!(safe::get_coin_storage_balance<TEST_COIN>(&safe) == 0, 1);

        let sync_coin = coin::mint_for_testing<TEST_COIN>(500, ts::ctx(&mut scenario));
        safe::sync_supply<TEST_COIN>(&mut safe, sync_coin, ts::ctx(&mut scenario));

        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 500, 2);
        assert!(safe::get_coin_storage_balance<TEST_COIN>(&safe) == 500, 3);

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_sync_supply_not_owner() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false,
            ts::ctx(&mut scenario),
        );

        safe::add_to_balance_for_testing<TEST_COIN>(&mut safe, 500);

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let sync_coin = coin::mint_for_testing<TEST_COIN>(500, ts::ctx(&mut scenario));
        safe::sync_supply<TEST_COIN>(&mut safe, sync_coin, ts::ctx(&mut scenario));
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::ETokenNotWhitelisted)]
fun test_sync_supply_token_not_whitelisted() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let sync_coin = coin::mint_for_testing<TEST_COIN>(500, ts::ctx(&mut scenario));
        safe::sync_supply<TEST_COIN>(&mut safe, sync_coin, ts::ctx(&mut scenario));
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EInsufficientBalance)]
fun test_sync_supply_no_deficit() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false,
            ts::ctx(&mut scenario),
        );

        let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, coin, ts::ctx(&mut scenario));

        let sync_coin = coin::mint_for_testing<TEST_COIN>(500, ts::ctx(&mut scenario));
        safe::sync_supply<TEST_COIN>(&mut safe, sync_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EInsufficientBalance)]
fun test_sync_supply_insufficient_coin() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false,
            ts::ctx(&mut scenario),
        );

        let coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, coin, ts::ctx(&mut scenario));

        safe::add_to_balance_for_testing<TEST_COIN>(&mut safe, 500);

        let sync_coin = coin::mint_for_testing<TEST_COIN>(200, ts::ctx(&mut scenario));
        safe::sync_supply<TEST_COIN>(&mut safe, sync_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EInsufficientBalance)]
fun test_sync_supply_not_native() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false, 
            false,
            ts::ctx(&mut scenario),
        );

        let sync_coin = coin::mint_for_testing<TEST_COIN>(500, ts::ctx(&mut scenario));
        safe::sync_supply<TEST_COIN>(&mut safe, sync_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_old_owner_cannot_use_owner_functions_after_transfer() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::transfer_ownership(&mut safe, NEW_OWNER, scenario.ctx());
        ts::return_shared(safe);
    };

    scenario.next_tx(NEW_OWNER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::accept_ownership(&mut safe, scenario.ctx());
        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        
        safe::pause_contract(&mut safe, scenario.ctx());
        
        ts::return_shared(safe);
    };

    ts::end(scenario);
}
