#[test_only]
module bridge_safe::deposit_transfer_tests;

use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::pausable;
use bridge_safe::safe::{Self, BridgeSafe};
use locked_token::bridge_token::{Self as br, BRIDGE_TOKEN};
use locked_token::treasury::{Self as lkt, Treasury, FromCoinCap};
use sui::clock;
use sui::coin;
use sui::test_scenario::{Self as ts, Scenario};

public struct TEST_COIN has drop {}
public struct NATIVE_COIN has drop {}
public struct NON_NATIVE_COIN has drop {}

const ADMIN: address = @0xa11ce;
const USER: address = @0xb0b;
const BRIDGE: address = @0xc0de;
const RECIPIENT: address = @0xdea1;
const RECIPIENT_VECTOR: vector<u8> = b"12345678901234567890123456789012";

const MIN_AMOUNT: u64 = 100;
const MAX_AMOUNT: u64 = 1000000;
const DEPOSIT_AMOUNT: u64 = 50000;

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
fun test_deposit_basic() {
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

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Create coin for deposit
        let coin = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        // Initial state
        assert!(safe::get_deposits_count(&safe) == 0, 0);
        assert!(safe::get_batches_count(&safe) == 0, 1);

        // Perform deposit
        safe::deposit<TEST_COIN>(
            &mut safe,
            coin,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );

        // Verify state changes
        assert!(safe::get_deposits_count(&safe) == 1, 2);
        assert!(safe::get_batches_count(&safe) == 1, 3);
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == DEPOSIT_AMOUNT, 4);

        // Verify batch was created and has deposit
        let (batch, _is_final) = safe::get_batch(&safe, 1, &clock);
        assert!(safe::get_batch_nonce(&batch) == 1, 5);
        assert!(safe::get_batch_deposits_count(&batch) == 1, 6);

        // Verify deposits in batch
        let (deposits, _) = safe::get_deposits(&safe, 1, &clock);
        assert!(vector::length(&deposits) == 1, 7);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_deposit_multiple_same_batch() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::set_batch_size(&mut safe, 5, ts::ctx(&mut scenario));

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

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Make 3 deposits (should all go to same batch)
        let coin1 = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
        let coin2 = coin::mint_for_testing<TEST_COIN>(2000, ts::ctx(&mut scenario));
        let coin3 = coin::mint_for_testing<TEST_COIN>(3000, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(
            &mut safe,
            coin1,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );
        safe::deposit<TEST_COIN>(
            &mut safe,
            coin2,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );
        safe::deposit<TEST_COIN>(
            &mut safe,
            coin3,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );

        // Should have 3 deposits, 1 batch
        assert!(safe::get_deposits_count(&safe) == 3, 0);
        assert!(safe::get_batches_count(&safe) == 1, 1);
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 6000, 2);

        // Verify batch has 3 deposits
        let (batch, _) = safe::get_batch(&safe, 1, &clock);
        assert!(safe::get_batch_deposits_count(&batch) == 3, 3);

        let (deposits, _) = safe::get_deposits(&safe, 1, &clock);
        assert!(vector::length(&deposits) == 3, 4);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_deposit_triggers_new_batch() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Set batch size to 2 for testing
        safe::set_batch_size(&mut safe, 2, ts::ctx(&mut scenario));

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

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Make 3 deposits - should create 2 batches
        let coin1 = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
        let coin2 = coin::mint_for_testing<TEST_COIN>(2000, ts::ctx(&mut scenario));
        let coin3 = coin::mint_for_testing<TEST_COIN>(3000, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(
            &mut safe,
            coin1,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );
        safe::deposit<TEST_COIN>(
            &mut safe,
            coin2,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );
        // Third deposit should trigger new batch
        safe::deposit<TEST_COIN>(
            &mut safe,
            coin3,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );

        // Should have 3 deposits, 2 batches
        assert!(safe::get_deposits_count(&safe) == 3, 0);
        assert!(safe::get_batches_count(&safe) == 2, 1);

        // First batch should have 2 deposits
        let (batch1, _) = safe::get_batch(&safe, 1, &clock);
        assert!(safe::get_batch_deposits_count(&batch1) == 2, 2);

        // Second batch should have 1 deposit
        let (batch2, _) = safe::get_batch(&safe, 2, &clock);
        assert!(safe::get_batch_deposits_count(&batch2) == 1, 3);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EInvalidRecipient)]
fun test_deposit_invalid_recipient() {
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

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(&mut safe, coin, b"0x0", &clock, ts::ctx(&mut scenario));

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_deposit_token_not_whitelisted() {
    let mut scenario = setup();

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(&mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario));

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EZeroAmount)]
fun test_deposit_zero_amount() {
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

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<TEST_COIN>(0, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(&mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario));

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EAmountBelowMinimum)]
fun test_deposit_amount_below_minimum() {
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

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<TEST_COIN>(MIN_AMOUNT - 1, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(&mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario));

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EAmountAboveMaximum)]
fun test_deposit_amount_above_maximum() {
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

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<TEST_COIN>(MAX_AMOUNT + 1, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(&mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario));

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pausable::EContractPaused)]
fun test_deposit_when_paused() {
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

        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(&mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario));

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_transfer_basic() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist and initialize supply
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let supply_coin = coin::mint_for_testing<TEST_COIN>(100000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, supply_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        // Verify initial balance
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 100000, 0);

        // Perform transfer
        let success = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            DEPOSIT_AMOUNT,
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(success, 1);
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 100000 - DEPOSIT_AMOUNT, 2);

        let bag_balance = safe::get_coin_storage_balance<TEST_COIN>(&safe);
        assert!(bag_balance == 100000 - DEPOSIT_AMOUNT, 10);
        assert!(bag_balance == safe::get_stored_coin_balance<TEST_COIN>(&mut safe), 11);

        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    // Verify recipient received the coin
    scenario.next_tx(RECIPIENT);
    {
        let coin = ts::take_from_sender<coin::Coin<TEST_COIN>>(&scenario);
        assert!(coin::value(&coin) == DEPOSIT_AMOUNT, 3);
        ts::return_to_sender(&scenario, coin);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_exact_balance() {
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

        // Initialize with exact amount we want to transfer
        let supply_coin = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, supply_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        // Transfer entire balance
        let success = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            DEPOSIT_AMOUNT,
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(success, 0);
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 0, 1);

        let bag_balance = safe::get_coin_storage_balance<TEST_COIN>(&safe);
        assert!(bag_balance == 0, 10);
        assert!(bag_balance == safe::get_stored_coin_balance<TEST_COIN>(&mut safe), 11);

        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_token_not_whitelisted() {
    let mut scenario = setup();

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        // Try to transfer non-whitelisted token - should return false
        let success = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            DEPOSIT_AMOUNT,
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(!success, 0);

        let bag_balance = safe::get_coin_storage_balance<TEST_COIN>(&safe);
        assert!(bag_balance == 0, 10);
        assert!(bag_balance == safe::get_stored_coin_balance<TEST_COIN>(&mut safe), 11);

        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_token_removed_from_whitelist() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist, initialize, then remove from whitelist
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let supply_coin = coin::mint_for_testing<TEST_COIN>(100000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, supply_coin, ts::ctx(&mut scenario));

        safe::remove_token_from_whitelist<TEST_COIN>(&mut safe, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        // Try to transfer removed token - should be okay - we will use whitelisted check only for deposits
        let success = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            DEPOSIT_AMOUNT,
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(success, 0);

        let bag_balance = safe::get_coin_storage_balance<TEST_COIN>(&safe);
        assert!(bag_balance == 100000 - DEPOSIT_AMOUNT, 10);
        assert!(bag_balance == safe::get_stored_coin_balance<TEST_COIN>(&mut safe), 11);

        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_insufficient_balance() {
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

        // Initialize with small amount
        let supply_coin = coin::mint_for_testing<TEST_COIN>(1000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, supply_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        // Try to transfer more than balance - should return false
        let success = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            DEPOSIT_AMOUNT, // Much larger than 1000
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(!success, 0);
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 1000, 1); // Balance unchanged

        let bag_balance = safe::get_coin_storage_balance<TEST_COIN>(&safe);
        assert!(bag_balance == 1000, 10);
        assert!(bag_balance == safe::get_stored_coin_balance<TEST_COIN>(&mut safe), 11);

        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_no_coin_storage() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        // Whitelist but don't initialize supply
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

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        // Try to transfer when no coins stored - should return false
        let success = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            DEPOSIT_AMOUNT,
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(!success, 0);

        let bag_balance = safe::get_coin_storage_balance<TEST_COIN>(&safe);
        assert!(bag_balance == 0, 10);
        assert!(bag_balance == safe::get_stored_coin_balance<TEST_COIN>(&mut safe), 11);

        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_multiple_partial() {
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

        let supply_coin = coin::mint_for_testing<TEST_COIN>(100000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, supply_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        // Multiple transfers
        let success1 = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            10000,
            &mut treasury,
            ts::ctx(&mut scenario),
        );
        let success2 = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            20000,
            &mut treasury,
            ts::ctx(&mut scenario),
        );
        let success3 = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            30000,
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(success1, 0);
        assert!(success2, 1);
        assert!(success3, 2);
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 40000, 3);

        let bag_balance = safe::get_coin_storage_balance<TEST_COIN>(&safe);
        assert!(bag_balance == 40000, 10);
        assert!(bag_balance == safe::get_stored_coin_balance<TEST_COIN>(&mut safe), 11);

        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_deposit_then_transfer_integration() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        safe::deposit<TEST_COIN>(&mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario));

        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == DEPOSIT_AMOUNT, 0);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        let success = safe::transfer<TEST_COIN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            DEPOSIT_AMOUNT,
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(success, 1);
        assert!(safe::get_stored_coin_balance<TEST_COIN>(&mut safe) == 0, 2);

        let bag_balance = safe::get_coin_storage_balance<TEST_COIN>(&safe);
        assert!(bag_balance == 0, 10);
        assert!(bag_balance == safe::get_stored_coin_balance<TEST_COIN>(&mut safe), 11);

        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}
