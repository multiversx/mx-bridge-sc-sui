#[test_only]
#[allow(unused_use)]
module bridge_safe::bridge_safe_tests;

use bridge_safe::pausable;
use bridge_safe::roles::{AdminCap, BridgeCap};
use bridge_safe::safe::{Self, BridgeSafe};
use bridge_safe::utils;
use shared_structs::shared_structs::{Self, TokenConfig, Batch, Deposit};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::test_utils;

const ADMIN: address = @0xA11CE;
const BRIDGE: address = @0xB0B;
const NON_ADMIN: address = @0xBAD;

fun setup_test(): (test_scenario::Scenario, BridgeSafe, AdminCap, BridgeCap) {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);
    let (safe, admin_cap, bridge_cap) = safe::publish(ctx, ADMIN, BRIDGE);
    (scenario, safe, admin_cap, bridge_cap)
}

fun cleanup_test(
    scenario: test_scenario::Scenario,
    safe: BridgeSafe,
    admin_cap: AdminCap,
    bridge_cap: BridgeCap,
) {
    test_utils::destroy(safe);
    test_utils::destroy(admin_cap);
    test_utils::destroy(bridge_cap);
    test_scenario::end(scenario);
}

#[test]
fun test_publish_safe() {
    let (scenario, safe, admin_cap, bridge_cap) = setup_test();

    assert!(safe::get_admin(&safe) == ADMIN, 0);
    assert!(safe::get_bridge_addr(&safe) == BRIDGE, 1);
    assert!(safe::get_batch_size(&safe) == 10, 2);
    assert!(safe::get_batches_count(&safe) == 0, 3);
    assert!(safe::get_deposits_count(&safe) == 0, 4);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_whitelist_token() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        1000,
        false,
        true,
        ctx,
    );

    assert!(safe::is_token_whitelisted<SUI>(&safe), 0);
    assert!(safe::get_token_min_limit<SUI>(&safe) == 100, 1);
    assert!(safe::get_token_max_limit<SUI>(&safe) == 1000, 2);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_remove_token_from_whitelist() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        1000,
        false,
        true,
        ctx,
    );

    assert!(safe::is_token_whitelisted<SUI>(&safe), 0);

    safe::remove_token_from_whitelist<SUI>(&mut safe, &admin_cap, ctx);

    assert!(!safe::is_token_whitelisted<SUI>(&safe), 1);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_set_batch_limits() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::set_batch_block_limit(&mut safe, &admin_cap, 20, ctx);
    assert!(safe::get_batch_block_limit(&safe) == 20, 0);

    safe::set_batch_size(&mut safe, &admin_cap, 50, ctx);
    assert!(safe::get_batch_size(&safe) == 50, 1);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_set_batch_settle_limit_when_paused() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    pausable::pause(safe::get_pause_mut(&mut safe));

    safe::set_batch_settle_limit(&mut safe, &admin_cap, 60, ctx);
    assert!(safe::get_batch_settle_limit(&safe) == 60, 0);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_set_token_limits() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        1000,
        false,
        true,
        ctx,
    );

    safe::set_token_min_limit<SUI>(&mut safe, &admin_cap, 200, ctx);
    assert!(safe::get_token_min_limit<SUI>(&safe) == 200, 0);

    safe::set_token_max_limit<SUI>(&mut safe, &admin_cap, 2000, ctx);
    assert!(safe::get_token_max_limit<SUI>(&safe) == 2000, 1);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_pausable_functionality() {
    let (scenario, mut safe, admin_cap, bridge_cap) = setup_test();

    pausable::assert_not_paused(safe::get_pause(&safe));

    pausable::pause(safe::get_pause_mut(&mut safe));
    pausable::assert_paused(safe::get_pause(&safe));

    pausable::unpause(safe::get_pause_mut(&mut safe));
    pausable::assert_not_paused(safe::get_pause(&safe));

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_batch_creation() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    assert!(safe::get_batches_count(&safe) == 0, 0);
    assert!(!safe::is_any_batch_in_progress(&safe), 1);

    safe::create_new_batch_internal(&mut safe, ctx);

    assert!(safe::get_batches_count(&safe) == 1, 2);

    let (batch, _is_final) = safe::get_batch(&safe, 1);
    assert!(safe::get_batch_nonce(&batch) == 1, 3);
    assert!(safe::get_batch_deposits_count(&batch) == 0, 4);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_utils_type_name_bytes() {
    let sui_bytes = utils::type_name_bytes<SUI>();
    let bool_bytes = utils::type_name_bytes<bool>();

    assert!(sui_bytes != bool_bytes, 0);

    let sui_bytes2 = utils::type_name_bytes<SUI>();
    assert!(sui_bytes == sui_bytes2, 1);
}

#[test]
fun test_token_whitelisting_status() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    assert!(!safe::is_token_whitelisted<SUI>(&safe), 0);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        1000,
        false,
        true,
        ctx,
    );

    assert!(safe::is_token_whitelisted<SUI>(&safe), 1);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::ETokenAlreadyExists)]
fun test_whitelist_token_already_exists() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        1000,
        false,
        true,
        ctx,
    );

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        200,
        2000,
        false,
        true,
        ctx,
    );

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::ENotAdmin)]
fun test_admin_only_functions_fail_for_non_admin() {
    let mut scenario = test_scenario::begin(NON_ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);

    let (mut safe, admin_cap, bridge_cap) = safe::publish(ctx, ADMIN, BRIDGE);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        1000,
        false,
        true,
        ctx,
    );

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::EBatchBlockLimitExceedsSettle)]
fun test_batch_block_limit_exceeds_settle_limit() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::set_batch_block_limit(&mut safe, &admin_cap, 50, ctx);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::EBatchSettleLimitBelowBlock)]
fun test_batch_settle_limit_below_block_limit() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    pausable::pause(safe::get_pause_mut(&mut safe));

    safe::set_batch_settle_limit(&mut safe, &admin_cap, 20, ctx);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::EBatchSizeTooLarge)]
fun test_batch_size_too_large() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::set_batch_size(&mut safe, &admin_cap, 150, ctx);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::EAmountBelowMinimum)]
fun test_deposit_amount_below_minimum() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        1000,
        false,
        true,
        ctx,
    );

    let coin = coin::mint_for_testing<SUI>(50, ctx);

    safe::deposit(&mut safe, coin, @0x123, ctx);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::EAmountAboveMaximum)]
fun test_deposit_amount_above_maximum() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        1000,
        false,
        true,
        ctx,
    );

    let coin = coin::mint_for_testing<SUI>(2000, ctx);

    safe::deposit(&mut safe, coin, @0x123, ctx);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_batch_progress_tracking() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    assert!(!safe::is_any_batch_in_progress(&safe), 0);

    safe::create_new_batch_internal(&mut safe, ctx);

    assert!(safe::get_batches_count(&safe) == 1, 1);

    let (batch, _is_final) = safe::get_batch(&safe, 1);
    assert!(safe::get_batch_nonce(&batch) == 1, 2);
    assert!(safe::get_batch_deposits_count(&batch) == 0, 3);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_empty_deposits_retrieval() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::create_new_batch_internal(&mut safe, ctx);

    let (deposits, _is_final) = safe::get_deposits(&safe, 1);
    assert!(vector::length(&deposits) == 0, 0);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_complete_bridge_flow_scenario_1() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    assert!(safe::get_admin(&safe) == ADMIN, 0);
    assert!(safe::get_bridge_addr(&safe) == BRIDGE, 1);
    assert!(safe::get_deposits_count(&safe) == 0, 2);
    assert!(safe::get_batches_count(&safe) == 0, 3);
    assert!(!safe::is_token_whitelisted<SUI>(&safe), 4);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        500,
        5000,
        false,
        true,
        ctx,
    );

    assert!(safe::is_token_whitelisted<SUI>(&safe), 5);
    assert!(safe::get_token_min_limit<SUI>(&safe) == 500, 6);
    assert!(safe::get_token_max_limit<SUI>(&safe) == 5000, 7);

    let coin1 = coin::mint_for_testing<SUI>(1000, ctx);
    let initial_balance = safe::get_stored_coin_balance<SUI>(&safe);
    assert!(initial_balance == 0, 8);

    safe::deposit(&mut safe, coin1, @0x123, ctx);

    assert!(safe::get_deposits_count(&safe) == 1, 9);
    assert!(safe::get_batches_count(&safe) == 1, 10);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 1000, 11);

    let (batch, _is_final) = safe::get_batch(&safe, 1);
    assert!(safe::get_batch_nonce(&batch) == 1, 12);
    assert!(safe::get_batch_deposits_count(&batch) == 1, 13);

    let (deposits, _deposits_final) = safe::get_deposits(&safe, 1);
    assert!(vector::length(&deposits) == 1, 14);

    let coin2 = coin::mint_for_testing<SUI>(2000, ctx);
    safe::deposit(&mut safe, coin2, @0x456, ctx);

    assert!(safe::get_deposits_count(&safe) == 2, 15);
    assert!(safe::get_batches_count(&safe) >= 1, 16);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 3000, 17);

    let total_batch_count = safe::get_batches_count(&safe);
    assert!(total_batch_count >= 1, 18);

    let mut i = 0;
    while (i < 8) {
        let coin = coin::mint_for_testing<SUI>(1000, ctx);
        safe::deposit(&mut safe, coin, @0x789, ctx);
        i = i + 1;
    };

    assert!(safe::get_deposits_count(&safe) == 10, 19);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 11000, 21);

    let transfer_amount = 1500;
    let recipient_addr = @0xabc;
    let transfer_success = safe::transfer<SUI>(
        &mut safe,
        &bridge_cap,
        recipient_addr,
        transfer_amount,
        ctx,
    );
    assert!(transfer_success, 22);

    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 9500, 23);

    safe::remove_token_from_whitelist<SUI>(&mut safe, &admin_cap, ctx);
    assert!(!safe::is_token_whitelisted<SUI>(&safe), 24);

    let coin_fail = coin::mint_for_testing<SUI>(1000, ctx);

    test_utils::destroy(coin_fail);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_multi_token_complex_scenario() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        100,
        10000,
        false,
        true,
        ctx,
    );

    let sui_coin1 = coin::mint_for_testing<SUI>(1000, ctx);
    let sui_coin2 = coin::mint_for_testing<SUI>(2000, ctx);
    let sui_coin3 = coin::mint_for_testing<SUI>(1500, ctx);

    let initial_balance = safe::get_stored_coin_balance<SUI>(&safe);
    assert!(initial_balance == 0, 0);

    safe::deposit(&mut safe, sui_coin1, @0x111, ctx);
    safe::deposit(&mut safe, sui_coin2, @0x222, ctx);
    safe::deposit(&mut safe, sui_coin3, @0x333, ctx);

    assert!(safe::get_deposits_count(&safe) == 3, 1);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 4500, 2);

    safe::set_token_min_limit<SUI>(&mut safe, &admin_cap, 200, ctx);
    safe::set_token_max_limit<SUI>(&mut safe, &admin_cap, 8000, ctx);

    assert!(safe::get_token_min_limit<SUI>(&safe) == 200, 3);
    assert!(safe::get_token_max_limit<SUI>(&safe) == 8000, 4);

    let sui_coin4 = coin::mint_for_testing<SUI>(3000, ctx);
    safe::deposit(&mut safe, sui_coin4, @0x444, ctx);

    assert!(safe::get_deposits_count(&safe) == 4, 5);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 7500, 6);

    let transfer1_success = safe::transfer<SUI>(&mut safe, &bridge_cap, @0xaaa, 1000, ctx);
    let transfer2_success = safe::transfer<SUI>(&mut safe, &bridge_cap, @0xbbb, 2000, ctx);
    let transfer3_success = safe::transfer<SUI>(&mut safe, &bridge_cap, @0xccc, 1500, ctx);

    assert!(transfer1_success, 7);
    assert!(transfer2_success, 8);
    assert!(transfer3_success, 9);

    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 3000, 10);

    let transfer_fail = safe::transfer<SUI>(&mut safe, &bridge_cap, @0xddd, 5000, ctx);
    assert!(transfer_fail == false, 11);

    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 3000, 12);

    let total_batches = safe::get_batches_count(&safe);
    assert!(total_batches >= 1, 13);

    assert!(safe::get_deposits_count(&safe) == 4, 14);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
fun test_edge_cases_and_limits_scenario() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(
        &mut safe,
        &admin_cap,
        1000,
        2000,
        false,
        true,
        ctx,
    );

    let coin_min = coin::mint_for_testing<SUI>(1000, ctx);
    safe::deposit(&mut safe, coin_min, @0x111, ctx);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 1000, 0);

    let coin_max = coin::mint_for_testing<SUI>(2000, ctx);
    safe::deposit(&mut safe, coin_max, @0x222, ctx);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 3000, 1);

    safe::set_batch_size(&mut safe, &admin_cap, 3, ctx);
    assert!(safe::get_batch_size(&safe) == 3, 2);

    let coin_trigger = coin::mint_for_testing<SUI>(1500, ctx);
    safe::deposit(&mut safe, coin_trigger, @0x333, ctx);

    assert!(safe::get_deposits_count(&safe) == 3, 4);
    assert!(safe::get_batches_count(&safe) >= 1, 3);

    pausable::pause(safe::get_pause_mut(&mut safe));
    pausable::assert_paused(safe::get_pause(&safe));

    let transfer_while_paused = safe::transfer<SUI>(&mut safe, &bridge_cap, @0xaaa, 500, ctx);
    assert!(transfer_while_paused, 5);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 4000, 6);

    safe::set_token_max_limit<SUI>(&mut safe, &admin_cap, 3000, ctx);
    assert!(safe::get_token_max_limit<SUI>(&safe) == 3000, 7);

    pausable::unpause(safe::get_pause_mut(&mut safe));
    pausable::assert_not_paused(safe::get_pause(&safe));

    let coin_after_unpause = coin::mint_for_testing<SUI>(1200, ctx);
    safe::deposit(&mut safe, coin_after_unpause, @0x444, ctx);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 5200, 8);

    safe::set_batch_block_limit(&mut safe, &admin_cap, 30, ctx);
    assert!(safe::get_batch_block_limit(&safe) == 30, 9);

    assert!(safe::get_deposits_count(&safe) == 4, 10);
    assert!(safe::get_batches_count(&safe) >= 1, 11);

    let final_transfer = safe::transfer<SUI>(&mut safe, &bridge_cap, @0xfff, 1000, ctx);
    assert!(final_transfer, 12);
    assert!(safe::get_stored_coin_balance<SUI>(&safe) == 4200, 13);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::ETokenNotWhitelisted)]
fun test_deposit_after_whitelist_removal() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 1000, false, true, ctx);
    safe::remove_token_from_whitelist<SUI>(&mut safe, &admin_cap, ctx);

    let coin = coin::mint_for_testing<SUI>(500, ctx);
    safe::deposit(&mut safe, coin, @0x123, ctx);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::EAmountBelowMinimum)]
fun test_deposit_below_updated_minimum() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 1000, false, true, ctx);

    safe::set_token_min_limit<SUI>(&mut safe, &admin_cap, 500, ctx);

    let coin = coin::mint_for_testing<SUI>(300, ctx);
    safe::deposit(&mut safe, coin, @0x123, ctx);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::safe::EAmountAboveMaximum)]
fun test_deposit_above_updated_maximum() {
    let (mut scenario, mut safe, admin_cap, bridge_cap) = setup_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 2000, false, true, ctx);

    safe::set_token_max_limit<SUI>(&mut safe, &admin_cap, 1000, ctx);

    let coin = coin::mint_for_testing<SUI>(1500, ctx);
    safe::deposit(&mut safe, coin, @0x123, ctx);

    cleanup_test(scenario, safe, admin_cap, bridge_cap);
}
