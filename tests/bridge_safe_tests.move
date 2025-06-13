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
    let mut scenario = test_scenario::begin(NON_ADMIN); // Start with non-admin
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
