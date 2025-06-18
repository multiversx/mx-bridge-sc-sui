#[test_only]
#[allow(unused_use)]
module bridge_safe::bridge_tests;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::pausable;
use bridge_safe::roles::{AdminCap, BridgeCap};
use bridge_safe::safe::{Self, BridgeSafe};
use shared_structs::shared_structs::{Batch, Deposit};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::test_utils;
use sui::vec_set;

const ADMIN: address = @0xA11CE;
const RELAYER1: address = @0xB0B;
const RELAYER2: address = @0xCAFE;
const RELAYER3: address = @0xDEAD;
const RELAYER4: address = @0xBEEF;
const NON_RELAYER: address = @0xBAD;
const RECIPIENT: address = @0x123;

fun setup_bridge_test(): (test_scenario::Scenario, Bridge, BridgeSafe, AdminCap, BridgeCap) {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);

    let (safe, admin_cap, bridge_cap) = safe::publish(ctx, ADMIN, RELAYER1);
    let safe_address = object::id_address(&safe);

    let board = vector[RELAYER1, RELAYER2, RELAYER3, RELAYER4];
    let bridge = bridge::initialize(board, 3, safe_address, ctx);

    (scenario, bridge, safe, admin_cap, bridge_cap)
}

fun cleanup_bridge_test(
    scenario: test_scenario::Scenario,
    bridge: Bridge,
    safe: BridgeSafe,
    admin_cap: AdminCap,
    bridge_cap: BridgeCap,
) {
    test_utils::destroy(bridge);
    test_utils::destroy(safe);
    test_utils::destroy(admin_cap);
    test_utils::destroy(bridge_cap);
    test_scenario::end(scenario);
}

#[test]
fun test_bridge_initialization() {
    let (scenario, bridge, safe, admin_cap, bridge_cap) = setup_bridge_test();

    assert!(bridge::get_admin(&bridge) == ADMIN, 0);
    assert!(bridge::get_quorum(&bridge) == 3, 1);
    assert!(bridge::get_batch_settle_block_count(&bridge) == 40, 2);
    assert!(bridge::is_relayer(&bridge, RELAYER1), 3);
    assert!(bridge::is_relayer(&bridge, RELAYER2), 4);
    assert!(bridge::is_relayer(&bridge, RELAYER3), 5);
    assert!(bridge::is_relayer(&bridge, RELAYER4), 6);
    assert!(!bridge::is_relayer(&bridge, NON_RELAYER), 7);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_set_quorum() {
    let (mut scenario, mut bridge, safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    bridge::set_quorum(&mut bridge, &admin_cap, 4, ctx);
    assert!(bridge::get_quorum(&bridge) == 4, 0);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_add_relayer() {
    let (mut scenario, mut bridge, safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    assert!(!bridge::is_relayer(&bridge, NON_RELAYER), 0);

    bridge::add_relayer(&mut bridge, &admin_cap, NON_RELAYER, ctx);
    assert!(bridge::is_relayer(&bridge, NON_RELAYER), 1);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_remove_relayer() {
    let (mut scenario, mut bridge, safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    assert!(bridge::is_relayer(&bridge, RELAYER1), 0);

    bridge::remove_relayer(&mut bridge, &admin_cap, RELAYER1, ctx);
    assert!(!bridge::is_relayer(&bridge, RELAYER1), 1);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_set_batch_settle_limit() {
    let (mut scenario, mut bridge, mut safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    pausable::pause(bridge::get_pause_mut(&mut bridge));

    bridge::set_batch_settle_limit(&mut bridge, &admin_cap, &safe, 60, ctx);
    assert!(bridge::get_batch_settle_block_count(&bridge) == 60, 0);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_was_batch_executed_initially_false() {
    let (scenario, bridge, safe, admin_cap, bridge_cap) = setup_bridge_test();

    assert!(!bridge::was_batch_executed(&bridge, 1), 0);
    assert!(!bridge::was_batch_executed(&bridge, 999), 1);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_get_statuses_after_execution_initially_false() {
    let (mut scenario, bridge, safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    let (was_executed, is_final) = bridge::get_statuses_after_execution(&bridge, 1, ctx);
    assert!(!was_executed, 0);
    assert!(!is_final, 1);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_execute_transfer_with_sufficient_balance() {
    let (mut scenario, mut bridge, mut safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 10000, false, true, ctx);

    test_scenario::next_tx(&mut scenario, RELAYER1);
    let ctx = test_scenario::ctx(&mut scenario);

    let deposit_coin = coin::mint_for_testing<SUI>(5000, ctx);
    safe::deposit(&mut safe, deposit_coin, RECIPIENT, ctx);

    let tokens = vector[b"SUI"];
    let recipients = vector[RECIPIENT];
    let amounts = vector[1000];
    let signatures = vector[b"sig1", b"sig2", b"sig3"];

    bridge::execute_transfer<SUI>(
        &mut bridge,
        &mut safe,
        &bridge_cap,
        tokens,
        recipients,
        amounts,
        1,
        signatures,
        ctx,
    );

    assert!(bridge::was_batch_executed(&bridge, 1), 0);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_execute_transfer_with_insufficient_balance() {
    let (mut scenario, mut bridge, mut safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 10000, false, true, ctx);

    test_scenario::next_tx(&mut scenario, RELAYER1);
    let ctx = test_scenario::ctx(&mut scenario);

    let deposit_coin = coin::mint_for_testing<SUI>(500, ctx);
    safe::deposit(&mut safe, deposit_coin, RECIPIENT, ctx);

    let tokens = vector[b"SUI"];
    let recipients = vector[RECIPIENT];
    let amounts = vector[1000];
    let signatures = vector[b"sig1", b"sig2", b"sig3"];

    bridge::execute_transfer<SUI>(
        &mut bridge,
        &mut safe,
        &bridge_cap,
        tokens,
        recipients,
        amounts,
        2,
        signatures,
        ctx,
    );

    assert!(bridge::was_batch_executed(&bridge, 2), 0);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
fun test_multiple_transfers_in_batch() {
    let (mut scenario, mut bridge, mut safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 10000, false, true, ctx);

    test_scenario::next_tx(&mut scenario, RELAYER1);
    let ctx = test_scenario::ctx(&mut scenario);

    let deposit_coin = coin::mint_for_testing<SUI>(10000, ctx);
    safe::deposit(&mut safe, deposit_coin, RECIPIENT, ctx);

    let tokens = vector[b"SUI", b"SUI", b"SUI"];
    let recipients = vector[RECIPIENT, @0x456, @0x789];
    let amounts = vector[1000, 2000, 1500];
    let signatures = vector[b"sig1", b"sig2", b"sig3"];

    bridge::execute_transfer<SUI>(
        &mut bridge,
        &mut safe,
        &bridge_cap,
        tokens,
        recipients,
        amounts,
        3,
        signatures,
        ctx,
    );

    assert!(bridge::was_batch_executed(&bridge, 3), 0);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::bridge::EQuorumTooLow)]
fun test_initialize_with_low_quorum() {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);

    let board = vector[RELAYER1, RELAYER2, RELAYER3];
    let bridge = bridge::initialize(board, 2, @0x1, ctx);

    test_utils::destroy(bridge);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge_safe::bridge::EBoardTooSmall)]
fun test_initialize_with_small_board() {
    let mut scenario = test_scenario::begin(ADMIN);
    let ctx = test_scenario::ctx(&mut scenario);

    let board = vector[RELAYER1, RELAYER2];
    let bridge = bridge::initialize(board, 3, @0x1, ctx);

    test_utils::destroy(bridge);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge_safe::bridge::EQuorumTooLow)]
fun test_set_quorum_too_low() {
    let (mut scenario, mut bridge, safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    bridge::set_quorum(&mut bridge, &admin_cap, 2, ctx);

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::bridge::ENotEnoughSignatures)]
fun test_execute_transfer_insufficient_signatures() {
    let (mut scenario, mut bridge, mut safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 10000, false, true, ctx);

    test_scenario::next_tx(&mut scenario, RELAYER1);
    let ctx = test_scenario::ctx(&mut scenario);

    let deposit_coin = coin::mint_for_testing<SUI>(5000, ctx);
    safe::deposit(&mut safe, deposit_coin, RECIPIENT, ctx);

    let tokens = vector[b"SUI"];
    let recipients = vector[RECIPIENT];
    let amounts = vector[1000];
    let signatures = vector[b"sig1", b"sig2"];

    bridge::execute_transfer<SUI>(
        &mut bridge,
        &mut safe,
        &bridge_cap,
        tokens,
        recipients,
        amounts,
        1,
        signatures,
        ctx,
    );

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::bridge::EBatchAlreadyExecuted)]
fun test_execute_transfer_batch_already_executed() {
    let (mut scenario, mut bridge, mut safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 10000, false, true, ctx);

    test_scenario::next_tx(&mut scenario, RELAYER1);
    let ctx = test_scenario::ctx(&mut scenario);

    let deposit_coin = coin::mint_for_testing<SUI>(5000, ctx);
    safe::deposit(&mut safe, deposit_coin, RECIPIENT, ctx);

    let tokens = vector[b"SUI"];
    let recipients = vector[RECIPIENT];
    let amounts = vector[1000];
    let signatures = vector[b"sig1", b"sig2", b"sig3"];

    bridge::execute_transfer<SUI>(
        &mut bridge,
        &mut safe,
        &bridge_cap,
        tokens,
        recipients,
        amounts,
        1,
        signatures,
        ctx,
    );

    bridge::execute_transfer<SUI>(
        &mut bridge,
        &mut safe,
        &bridge_cap,
        tokens,
        recipients,
        amounts,
        1,
        signatures,
        ctx,
    );

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = bridge_safe::bridge::ENotRelayer)]
fun test_execute_transfer_not_relayer() {
    let (mut scenario, mut bridge, mut safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 10000, false, true, ctx);

    test_scenario::next_tx(&mut scenario, NON_RELAYER);
    let ctx = test_scenario::ctx(&mut scenario);

    let deposit_coin = coin::mint_for_testing<SUI>(5000, ctx);
    safe::deposit(&mut safe, deposit_coin, RECIPIENT, ctx);

    let tokens = vector[b"SUI"];
    let recipients = vector[RECIPIENT];
    let amounts = vector[1000];
    let signatures = vector[b"sig1", b"sig2", b"sig3"];

    bridge::execute_transfer<SUI>(
        &mut bridge,
        &mut safe,
        &bridge_cap,
        tokens,
        recipients,
        amounts,
        1,
        signatures,
        ctx,
    );

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}

#[test]
#[expected_failure(abort_code = 0)]
fun test_execute_transfer_when_paused() {
    let (mut scenario, mut bridge, mut safe, admin_cap, bridge_cap) = setup_bridge_test();
    let ctx = test_scenario::ctx(&mut scenario);

    safe::whitelist_token<SUI>(&mut safe, &admin_cap, 100, 10000, false, true, ctx);

    pausable::pause(bridge::get_pause_mut(&mut bridge));

    test_scenario::next_tx(&mut scenario, RELAYER1);
    let ctx = test_scenario::ctx(&mut scenario);

    let deposit_coin = coin::mint_for_testing<SUI>(5000, ctx);
    safe::deposit(&mut safe, deposit_coin, RECIPIENT, ctx);

    let tokens = vector[b"SUI"];
    let recipients = vector[RECIPIENT];
    let amounts = vector[1000];
    let signatures = vector[b"sig1", b"sig2", b"sig3"];

    bridge::execute_transfer<SUI>(
        &mut bridge,
        &mut safe,
        &bridge_cap,
        tokens,
        recipients,
        amounts,
        1,
        signatures,
        ctx,
    );

    cleanup_bridge_test(scenario, bridge, safe, admin_cap, bridge_cap);
}
