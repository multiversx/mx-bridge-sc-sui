#[test_only]
module bridge_safe::bridge_comprehensive_tests;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::roles::{AdminCap, BridgeCap};
use bridge_safe::safe::{Self, BridgeSafe};
use std::debug;
use std::hash::{Self, sha3_256};
use sui::clock;
use sui::hash::blake2b256;
use sui::test_scenario as ts;

public struct TEST_COIN has drop {}

const ADMIN: address = @0xa11ce;
const RELAYER1: address = @0xb0b;
const RELAYER2: address = @0xc0de;
const RELAYER3: address = @0xd00d;
const RELAYER4: address = @0xe11e;
const USER: address = @0xf00d;

const INITIAL_QUORUM: u64 = 3;
const MIN_AMOUNT: u64 = 100;
const MAX_AMOUNT: u64 = 1000000;

const PK1: vector<u8> = b"12345678901234567890123456789012";
const PK2: vector<u8> = b"abcdefghijklmnopqrstuvwxyz123456";
const PK3: vector<u8> = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";
const PK4: vector<u8> = b"98765432109876543210987654321098";

#[test]
fun test_initialize_bridge_success() {
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
        let bridge = ts::take_shared<Bridge>(&scenario);

        assert!(bridge::get_quorum(&bridge) == INITIAL_QUORUM, 0);
        assert!(bridge::get_admin(&bridge) == ADMIN, 1);
        assert!(bridge::is_relayer(&bridge, RELAYER1), 2);
        assert!(bridge::is_relayer(&bridge, RELAYER2), 3);
        assert!(bridge::is_relayer(&bridge, RELAYER3), 4);
        assert!(!bridge::is_relayer(&bridge, RELAYER4), 5);
        assert!(bridge::get_relayer_count(&bridge) == 3, 6);

        let pause = bridge::get_pause(&bridge);
        assert!(!pause, 7);

        ts::return_shared(bridge);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EQuorumTooLow)]
fun test_initialize_bridge_quorum_too_low() {
    let mut scenario = ts::begin(ADMIN);
    {
        safe::init_for_testing(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            2,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EBoardTooSmall)]
fun test_initialize_bridge_board_too_small() {
    let mut scenario = ts::begin(ADMIN);
    {
        safe::init_for_testing(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        let board = vector[RELAYER1, RELAYER2];
        let public_keys = vector[PK1, PK2];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };
    ts::end(scenario);
}

#[test]
fun test_set_quorum_success() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3, RELAYER4];
        let public_keys = vector[PK1, PK2, PK3, PK4];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::set_quorum(&mut bridge, &admin_cap, 4, ts::ctx(&mut scenario));
        assert!(bridge::get_quorum(&bridge) == 4, 0);

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ENotAdmin)]
fun test_set_quorum_not_admin() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::set_quorum(&mut bridge, &admin_cap, 4, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_add_relayer_success() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        assert!(!bridge::is_relayer(&bridge, RELAYER4), 0);
        assert!(bridge::get_relayer_count(&bridge) == 3, 1);

        bridge::add_relayer(&mut bridge, &admin_cap, RELAYER4, PK4, ts::ctx(&mut scenario));

        assert!(bridge::is_relayer(&bridge, RELAYER4), 2);
        assert!(bridge::get_relayer_count(&bridge) == 4, 3);

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_remove_relayer_success() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3, RELAYER4];
        let public_keys = vector[PK1, PK2, PK3, PK4];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        assert!(bridge::is_relayer(&bridge, RELAYER4), 0);
        assert!(bridge::get_relayer_count(&bridge) == 4, 1);

        bridge::remove_relayer(&mut bridge, &admin_cap, RELAYER4, ts::ctx(&mut scenario));

        assert!(!bridge::is_relayer(&bridge, RELAYER4), 2);
        assert!(bridge::get_relayer_count(&bridge) == 3, 3);

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ECannotRemoveRelayerBelowQuorum)]
fun test_remove_relayer_below_quorum() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::remove_relayer(&mut bridge, &admin_cap, RELAYER3, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_pause_unpause_contract() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        let pause = bridge::get_pause(&bridge);
        assert!(!pause, 0);

        bridge::pause_contract(&mut bridge, &admin_cap, ts::ctx(&mut scenario));

        let pause = bridge::get_pause(&bridge);
        assert!(pause, 1);

        bridge::unpause_contract(&mut bridge, &admin_cap, ts::ctx(&mut scenario));

        let pause = bridge::get_pause(&bridge);
        assert!(!pause, 2);

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_getter_functions() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        assert!(bridge::get_quorum(&bridge) == INITIAL_QUORUM, 0);
        assert!(bridge::get_admin(&bridge) == ADMIN, 1);
        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == 5 * 60 * 1000, 2);
        assert!(bridge::get_relayer_count(&bridge) == 3, 3);

        assert!(bridge::is_relayer(&bridge, RELAYER1), 4);
        assert!(bridge::is_relayer(&bridge, RELAYER2), 5);
        assert!(bridge::is_relayer(&bridge, RELAYER3), 6);
        assert!(!bridge::is_relayer(&bridge, RELAYER4), 7);
        assert!(!bridge::is_relayer(&bridge, USER), 8);

        let pause = bridge::get_pause(&bridge);
        assert!(!pause, 9);

        assert!(!bridge::was_batch_executed(&bridge, 1), 10);
        assert!(!bridge::was_batch_executed(&bridge, 999), 11);

        let (statuses, is_final) = bridge::get_statuses_after_execution(&bridge, 1, &clock);
        assert!(vector::length(&statuses) == 0, 12);
        assert!(!is_final, 13);

        ts::return_shared(bridge);
        ts::return_shared(safe);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
fun test_set_admin_success() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        assert!(bridge::get_admin(&bridge) == ADMIN, 0);

        bridge::set_admin(&mut bridge, &admin_cap, USER, ts::ctx(&mut scenario));

        assert!(bridge::get_admin(&bridge) == USER, 1);

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ENotAdmin)]
fun test_set_admin_not_admin() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::set_admin(&mut bridge, &admin_cap, USER, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
fun test_set_batch_settle_timeout_success() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
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
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        bridge::pause_contract(&mut bridge, &admin_cap, ts::ctx(&mut scenario));

        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == 5 * 60 * 1000, 0);

        let new_timeout = 30 * 60 * 1000; // 30 minutes
        bridge::set_batch_settle_timeout_ms(
            &mut bridge,
            &admin_cap,
            &safe,
            new_timeout,
            &clock,
            ts::ctx(&mut scenario),
        );

        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == new_timeout, 1);

        ts::return_shared(bridge);
        ts::return_shared(safe);
        ts::return_to_address(ADMIN, admin_cap);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ENotAdmin)]
fun test_set_batch_settle_timeout_not_admin() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        bridge::set_batch_settle_timeout_ms(
            &mut bridge,
            &admin_cap,
            &safe,
            30 * 60 * 1000,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(bridge);
        ts::return_shared(safe);
        ts::return_to_address(ADMIN, admin_cap);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EInvalidSignatureLength)]
fun test_execute_transfer_invalid_signature_length() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, RELAYER1);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let recipients = vector[USER];
        let amounts = vector[1000];
        let deposit_nonces = vector[1];
        let batch_nonce_mvx = 1;

        let invalid_signatures = vector[b"short", b"too_short", b"also_short"];

        bridge::execute_transfer<TEST_COIN>(
            &mut bridge,
            &mut safe,
            recipients,
            amounts,
            deposit_nonces,
            batch_nonce_mvx,
            invalid_signatures,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(bridge);
        ts::return_shared(safe);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EQuorumNotReached)]
fun test_execute_transfer_insufficient_signatures() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, RELAYER1);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let recipients = vector[USER];
        let amounts = vector[1000];
        let deposit_nonces = vector[1];
        let batch_nonce_mvx = 1;

        let mut mock_sig1 = PK1;
        vector::append(
            &mut mock_sig1,
            b"0123456789012345678901234567890123456789012345678901234567890123",
        );
        let mut mock_sig2 = PK2;
        vector::append(
            &mut mock_sig2,
            b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789AB",
        );

        let signatures = vector[mock_sig1, mock_sig2];

        bridge::execute_transfer<TEST_COIN>(
            &mut bridge,
            &mut safe,
            recipients,
            amounts,
            deposit_nonces,
            batch_nonce_mvx,
            signatures,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(bridge);
        ts::return_shared(safe);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EInvalidSignatureLength)]
fun test_add_relayer_invalid_public_key_length() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        let invalid_pk = b"too_short_key";
        bridge::add_relayer(&mut bridge, &admin_cap, RELAYER4, invalid_pk, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ENotAdmin)]
fun test_add_relayer_not_admin() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::add_relayer(&mut bridge, &admin_cap, RELAYER4, PK4, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ENotAdmin)]
fun test_remove_relayer_not_admin() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3, RELAYER4];
        let public_keys = vector[PK1, PK2, PK3, PK4];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::remove_relayer(&mut bridge, &admin_cap, RELAYER4, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ENotAdmin)]
fun test_pause_contract_not_admin() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::pause_contract(&mut bridge, &admin_cap, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ENotAdmin)]
fun test_unpause_contract_not_admin() {
    let mut scenario = ts::begin(ADMIN);

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
            ts::ctx(&mut scenario),
        );

        let board = vector[RELAYER1, RELAYER2, RELAYER3];
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            board,
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
        ts::return_to_sender(&scenario, admin_cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::pause_contract(&mut bridge, &admin_cap, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::next_tx(&mut scenario, USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let admin_cap = ts::take_from_address<AdminCap>(&scenario, ADMIN);

        bridge::unpause_contract(&mut bridge, &admin_cap, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_to_address(ADMIN, admin_cap);
    };

    ts::end(scenario);
}

const USER1: address = @0x8a42f7e422c48a26e39dc424d883d6a4ed3e9d0dfa9932d752cc7441e75b994f;
const USER2: address = @0xc0de;
const USER3: address = @0xd00d;

#[test]
fun test_construct_batch_message() {
    let batch_id = 1;
    let tokens = vector[
        b"0x8ca6fd3d13d8de0f00492d2ddc750a0072217b2ab36d1ec85bb015390299fafe::test_coin::TEST_COIN",
        b"0x8ca6fd3d13d8de0f00492d2ddc750a0072217b2ab36d1ec85bb015390299fafe::test_coin::TEST_COIN",
    ];
    let recipients = vector[USER1, USER1];
    let amounts = vector[2450, 250];
    let deposit_nonces = vector[1, 2];

    let message = bridge::construct_batch_message(
        batch_id,
        &tokens,
        &recipients,
        &amounts,
        &deposit_nonces,
    );

    // print the message
    debug::print(&message);

    let message_hash = hash::sha3_256(message);
    debug::print(&message_hash);
}
