#[test_only]
module bridge_safe::deposit_transfer_tests;

use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::pausable;
use bridge_safe::safe::{Self, BridgeSafe};
use bridge_safe::xmn_mint_cap_adapter;
use locked_token::bridge_token::{Self as br, BRIDGE_TOKEN};
use locked_token::treasury::{Self as lkt, Treasury, FromCoinCap};
use sui::clock;
use sui::coin;
use sui::deny_list::DenyList;
use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils;
use treasury::treasury::{Self as stablecoin_treasury, Treasury as XmnTreasury};

public struct TEST_COIN has drop {}
public struct NATIVE_COIN has drop {}
public struct NON_NATIVE_COIN has drop {}
public struct MINT_BURN_COIN has drop {}
// DEPOSIT_TRANSFER_TESTS matches the module name — required for OTW use in create_regulated_currency_v2
public struct DEPOSIT_TRANSFER_TESTS has drop {}

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
            false,
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
            false,
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
            false,
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
            false,
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
            false,
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
            false,
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
            false,
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
            false,
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
            false,
            ts::ctx(&mut scenario),
        );

        let supply_coin = coin::mint_for_testing<TEST_COIN>(100000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, supply_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

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

        ts::return_shared(treasury);
        ts::return_shared(safe);
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
            false,
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
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

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

        ts::return_shared(treasury);
        ts::return_shared(safe);
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
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

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

        ts::return_shared(treasury);
        ts::return_shared(safe);
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
            false,
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
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

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

        ts::return_shared(treasury);
        ts::return_shared(safe);
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
            false,
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
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

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

        ts::return_shared(treasury);
        ts::return_shared(safe);
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
            false,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

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

        ts::return_shared(treasury);
        ts::return_shared(safe);
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
            false,
            ts::ctx(&mut scenario),
        );

        let supply_coin = coin::mint_for_testing<TEST_COIN>(100000, ts::ctx(&mut scenario));
        safe::init_supply<TEST_COIN>(&mut safe, supply_coin, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

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

        ts::return_shared(treasury);
        ts::return_shared(safe);
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
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

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

        ts::return_shared(treasury);
        ts::return_shared(safe);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EIncompatibleTokenFlags)]
fun test_whitelist_rejects_mint_burn_and_locked_combination() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token_internal<MINT_BURN_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false,
            option::some(object::id_from_address(@0x1234)),
            true,
            true,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EIncompatibleTokenFlags)]
fun test_set_token_is_locked_rejects_mint_burn_token() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::set_token_is_locked<MINT_BURN_COIN>(&mut safe, true, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EIncompatibleTokenFlags)]
fun test_set_token_is_mint_burn_rejects_locked_token() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            ts::ctx(&mut scenario),
        );
        safe::set_token_is_mint_burn<TEST_COIN>(&mut safe, true, ts::ctx(&mut scenario));

        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_locked_token_path_decreases_balance() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

        safe::whitelist_token<BRIDGE_TOKEN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            ts::ctx(&mut scenario),
        );

        lkt::mint_coin_to_receiver<BRIDGE_TOKEN>(
            &mut treasury,
            DEPOSIT_AMOUNT,
            USER,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(treasury);
        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let bridge_coin = ts::take_from_sender<coin::Coin<BRIDGE_TOKEN>>(&scenario);
        safe::deposit<BRIDGE_TOKEN>(
            &mut safe,
            bridge_coin,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_stored_coin_balance<BRIDGE_TOKEN>(&mut safe) == DEPOSIT_AMOUNT, 0);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };

    scenario.next_tx(BRIDGE);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let mut treasury = ts::take_shared<Treasury<BRIDGE_TOKEN>>(&scenario);

        let success = safe::transfer<BRIDGE_TOKEN>(
            &mut safe,
            &bridge_cap,
            RECIPIENT,
            DEPOSIT_AMOUNT,
            &mut treasury,
            ts::ctx(&mut scenario),
        );

        assert!(success, 1);
        assert!(safe::get_stored_coin_balance<BRIDGE_TOKEN>(&mut safe) == 0, 2);

        ts::return_shared(treasury);
        ts::return_shared(safe);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

// ===========================
// Mint-Burn Deposit Tests
// ===========================

/// Whitelist MINT_BURN_COIN as a mint-burn token, using a dummy treasury ID.
/// The treasury ID is only stored for SDK reference — not validated on deposit.
fun setup_mint_burn(): Scenario {
    let mut s = setup();
    s.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&s);
        safe::whitelist_token_internal<MINT_BURN_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false,
            option::some(object::id_from_address(@0x1234)),
            true,
            false,
            s.ctx(),
        );
        ts::return_shared(safe);
    };
    s
}

/// Set up a BridgeSafe + Treasury<DEPOSIT_TRANSFER_TESTS> + DenyList.
/// Used for tests that call the real deposit_mint_burn (e.g. cap-not-registered).
fun setup_with_treasury(): Scenario {
    // deny_list::create_for_test requires sender == @0x0 (system address)
    let mut s = ts::begin(@0x0);
    br::init_for_testing(s.ctx());
    s.next_tx(@0x0);
    {
        sui::deny_list::create_for_testing(s.ctx());
        let otw = test_utils::create_one_time_witness<DEPOSIT_TRANSFER_TESTS>();
        let (treasury_cap, deny_cap, metadata) = coin::create_regulated_currency_v2(
            otw,
            6,
            b"DT",
            b"Deposit Transfer Test",
            b"",
            option::none(),
            true,
            s.ctx(),
        );
        let t = stablecoin_treasury::new(
            treasury_cap,
            deny_cap,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            s.ctx(),
        );
        transfer::public_share_object(t);
        transfer::public_share_object(metadata);

        let mut bridge_token_treasury = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        lkt::transfer_to_coin_cap<BRIDGE_TOKEN>(&mut bridge_token_treasury, ADMIN, s.ctx());
        lkt::transfer_from_coin_cap<BRIDGE_TOKEN>(&mut bridge_token_treasury, ADMIN, s.ctx());
        ts::return_shared(bridge_token_treasury);
    };
    // BridgeSafe created by ADMIN so ADMIN is the owner for whitelist calls
    s.next_tx(ADMIN);
    {
        let from_cap_db = s.take_from_address<FromCoinCap<BRIDGE_TOKEN>>(ADMIN);
        safe::init_for_testing(from_cap_db, s.ctx());
    };
    s
}

#[test]
fun test_deposit_mint_burn_basic() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<MINT_BURN_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        assert!(safe::get_deposits_count(&safe) == 0, 0);
        assert!(safe::get_batches_count(&safe) == 0, 1);

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe,
            coin,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );

        assert!(safe::get_deposits_count(&safe) == 1, 2);
        assert!(safe::get_batches_count(&safe) == 1, 3);
        // Coin was burned, not stored in bag
        assert!(safe::get_coin_storage_balance<MINT_BURN_COIN>(&safe) == 0, 4);
        // But total_balance accounting is updated
        assert!(safe::get_stored_coin_balance<MINT_BURN_COIN>(&mut safe) == DEPOSIT_AMOUNT, 5);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_deposit_mint_burn_batch_data() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<MINT_BURN_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe,
            coin,
            RECIPIENT_VECTOR,
            &clock,
            ts::ctx(&mut scenario),
        );

        let (batch, _) = safe::get_batch(&safe, 1, &clock);
        assert!(safe::get_batch_nonce(&batch) == 1, 0);
        assert!(safe::get_batch_deposits_count(&batch) == 1, 1);

        let (deposits, _) = safe::get_deposits(&safe, 1, &clock);
        assert!(vector::length(&deposits) == 1, 2);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_deposit_mint_burn_multiple_same_batch() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::set_batch_size(&mut safe, 5, ts::ctx(&mut scenario));
        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let coin1 = coin::mint_for_testing<MINT_BURN_COIN>(1000, ts::ctx(&mut scenario));
        let coin2 = coin::mint_for_testing<MINT_BURN_COIN>(2000, ts::ctx(&mut scenario));
        let coin3 = coin::mint_for_testing<MINT_BURN_COIN>(3000, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin1, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );
        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin2, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );
        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin3, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );

        assert!(safe::get_deposits_count(&safe) == 3, 0);
        assert!(safe::get_batches_count(&safe) == 1, 1);
        assert!(safe::get_stored_coin_balance<MINT_BURN_COIN>(&mut safe) == 6000, 2);

        let (batch, _) = safe::get_batch(&safe, 1, &clock);
        assert!(safe::get_batch_deposits_count(&batch) == 3, 3);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_deposit_mint_burn_triggers_new_batch() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::set_batch_size(&mut safe, 2, ts::ctx(&mut scenario));
        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let coin1 = coin::mint_for_testing<MINT_BURN_COIN>(1000, ts::ctx(&mut scenario));
        let coin2 = coin::mint_for_testing<MINT_BURN_COIN>(2000, ts::ctx(&mut scenario));
        let coin3 = coin::mint_for_testing<MINT_BURN_COIN>(3000, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin1, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );
        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin2, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );
        // Third deposit overflows batch_size=2, creates a new batch
        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin3, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );

        assert!(safe::get_deposits_count(&safe) == 3, 0);
        assert!(safe::get_batches_count(&safe) == 2, 1);

        let (batch1, _) = safe::get_batch(&safe, 1, &clock);
        assert!(safe::get_batch_deposits_count(&batch1) == 2, 2);

        let (batch2, _) = safe::get_batch(&safe, 2, &clock);
        assert!(safe::get_batch_deposits_count(&batch2) == 1, 3);

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EInvalidRecipient)]
fun test_deposit_mint_burn_invalid_recipient() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<MINT_BURN_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin, b"0x0", &clock, ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EZeroAmount)]
fun test_deposit_mint_burn_zero_amount() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<MINT_BURN_COIN>(0, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EAmountBelowMinimum)]
fun test_deposit_mint_burn_below_minimum() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<MINT_BURN_COIN>(MIN_AMOUNT - 1, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EAmountAboveMaximum)]
fun test_deposit_mint_burn_above_maximum() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<MINT_BURN_COIN>(MAX_AMOUNT + 1, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = safe::EIncompatibleTokenFlags)]
fun test_deposit_mint_burn_wrong_variant() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        // Whitelist as NATIVE — calling deposit_mint_burn_for_testing should fail
        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false,
            ts::ctx(&mut scenario),
        );
        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<TEST_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<TEST_COIN>(
            &mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}

/// Tests that deposit_mint_burn aborts when no MintCap is registered for the token.
/// Uses the real deposit_mint_burn function (not the testing bypass) with a proper
/// Treasury + DenyList. The abort happens before the treasury is accessed.
#[test]
#[expected_failure(abort_code = xmn_mint_cap_adapter::EMintBurnCapNotFound)]
fun test_deposit_mint_burn_cap_not_registered() {
    let mut scenario = setup_with_treasury();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);
        let deny_list = ts::take_shared<DenyList>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        safe::whitelist_token_internal<DEPOSIT_TRANSFER_TESTS>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false,
            option::some(object::id(&treasury)),
            true,
            false,
            ts::ctx(&mut scenario),
        );

        let coin = coin::mint_for_testing<DEPOSIT_TRANSFER_TESTS>(
            DEPOSIT_AMOUNT,
            ts::ctx(&mut scenario),
        );

        // No MintCap registered — expect EMintBurnCapNotFound
        xmn_mint_cap_adapter::deposit<DEPOSIT_TRANSFER_TESTS>(
            &mut safe,
            coin,
            RECIPIENT_VECTOR,
            &clock,
            &mut treasury,
            &deny_list,
            ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_shared(deny_list);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pausable::EContractPaused)]
fun test_deposit_mint_burn_when_paused() {
    let mut scenario = setup_mint_burn();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        safe::pause_contract(&mut safe, ts::ctx(&mut scenario));
        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        let coin = coin::mint_for_testing<MINT_BURN_COIN>(DEPOSIT_AMOUNT, ts::ctx(&mut scenario));

        safe::deposit_mint_burn_for_testing<MINT_BURN_COIN>(
            &mut safe, coin, RECIPIENT_VECTOR, &clock, ts::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        ts::return_shared(safe);
    };
    ts::end(scenario);
}


#[test]
fun test_transfer_mint_burn_not_configured() {
    let mut scenario = setup_with_treasury();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);
        let deny_list = ts::take_shared<DenyList>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        let success = xmn_mint_cap_adapter::transfer<DEPOSIT_TRANSFER_TESTS>(
            &mut safe, &bridge_cap, RECIPIENT, DEPOSIT_AMOUNT, &mut treasury, &deny_list, ts::ctx(&mut scenario),
        );
        assert!(!success, 0);
        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_shared(deny_list);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_mint_burn_wrong_variant() {
    let mut scenario = setup_with_treasury();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);

        safe::whitelist_token<DEPOSIT_TRANSFER_TESTS>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            false,
            ts::ctx(&mut scenario),
        );
        let supply = coin::mint_for_testing<DEPOSIT_TRANSFER_TESTS>(DEPOSIT_AMOUNT * 2, ts::ctx(&mut scenario));
        safe::init_supply<DEPOSIT_TRANSFER_TESTS>(&mut safe, supply, ts::ctx(&mut scenario));
        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);
        let deny_list = ts::take_shared<DenyList>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);

        let success = xmn_mint_cap_adapter::transfer<DEPOSIT_TRANSFER_TESTS>(
            &mut safe, &bridge_cap, RECIPIENT, DEPOSIT_AMOUNT, &mut treasury, &deny_list, ts::ctx(&mut scenario),
        );
        assert!(!success, 0);
        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_shared(deny_list);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_mint_burn_zero_balance() {
    let mut scenario = setup_with_treasury();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);

        safe::whitelist_token_internal<DEPOSIT_TRANSFER_TESTS>(
            &mut safe, MIN_AMOUNT, MAX_AMOUNT, false,
            option::some(object::id(&treasury)), true, false, ts::ctx(&mut scenario),
        );
        ts::return_shared(safe);
        ts::return_shared(treasury);
    };

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);
        let deny_list = ts::take_shared<DenyList>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        // balance=0 < DEPOSIT_AMOUNT → returns false
        let success = xmn_mint_cap_adapter::transfer<DEPOSIT_TRANSFER_TESTS>(
            &mut safe, &bridge_cap, RECIPIENT, DEPOSIT_AMOUNT, &mut treasury, &deny_list, ts::ctx(&mut scenario),
        );
        assert!(!success, 0);
        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_shared(deny_list);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_mint_burn_insufficient_balance() {
    let mut scenario = setup_with_treasury();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);
        safe::whitelist_token_internal<DEPOSIT_TRANSFER_TESTS>(
            &mut safe, MIN_AMOUNT, MAX_AMOUNT, false,
            option::some(object::id(&treasury)), true, false, ts::ctx(&mut scenario),
        );

        safe::add_to_balance_for_testing<DEPOSIT_TRANSFER_TESTS>(&mut safe, DEPOSIT_AMOUNT - 1);
        ts::return_shared(safe);
        ts::return_shared(treasury);
    };

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);
        let deny_list = ts::take_shared<DenyList>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let success = xmn_mint_cap_adapter::transfer<DEPOSIT_TRANSFER_TESTS>(
            &mut safe, &bridge_cap, RECIPIENT, DEPOSIT_AMOUNT, &mut treasury, &deny_list, ts::ctx(&mut scenario),
        );
        assert!(!success, 0);
        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_shared(deny_list);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_transfer_mint_burn_cap_not_registered() {
    let mut scenario = setup_with_treasury();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);
        safe::whitelist_token_internal<DEPOSIT_TRANSFER_TESTS>(
            &mut safe, MIN_AMOUNT, MAX_AMOUNT, false,
            option::some(object::id(&treasury)), true, false, ts::ctx(&mut scenario),
        );

        safe::add_to_balance_for_testing<DEPOSIT_TRANSFER_TESTS>(&mut safe, DEPOSIT_AMOUNT);
        ts::return_shared(safe);
        ts::return_shared(treasury);
    };

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = ts::take_shared<XmnTreasury<DEPOSIT_TRANSFER_TESTS>>(&scenario);
        let deny_list = ts::take_shared<DenyList>(&scenario);
        let bridge_cap = ts::take_from_address<BridgeCap>(&scenario, ADMIN);
        let success = xmn_mint_cap_adapter::transfer<DEPOSIT_TRANSFER_TESTS>(
            &mut safe, &bridge_cap, RECIPIENT, DEPOSIT_AMOUNT, &mut treasury, &deny_list, ts::ctx(&mut scenario),
        );
        assert!(!success, 0);
        ts::return_shared(safe);
        ts::return_shared(treasury);
        ts::return_shared(deny_list);
        ts::return_to_address(ADMIN, bridge_cap);
    };

    ts::end(scenario);
}
