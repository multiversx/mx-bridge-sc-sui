#[test_only]
module bridge_safe::bridge_comprehensive_tests;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::safe::{Self, BridgeSafe};
use bridge_safe::utils;
use locked_token::bridge_token::{Self as br, BRIDGE_TOKEN};
use locked_token::treasury::{Self as lkt, Treasury, FromCoinCap};
use sui::clock;
use sui::test_scenario::{Self as ts, Scenario};
use sui_extensions::two_step_role::ESenderNotActiveRole;

public struct TEST_COIN has drop {}

const ADMIN: address = @0xa11ce;
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
fun test_initialize_bridge_success() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let safe_addr = object::id_address(&safe);
        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            safe_addr,
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let bridge = ts::take_shared<Bridge>(&scenario);

        let pk1 = PK1;
        let pk2 = PK2;
        let pk3 = PK3;
        let relayer1 = bridge::getAddressFromPublicKeyTest(&pk1);
        let relayer2 = bridge::getAddressFromPublicKeyTest(&pk2);
        let relayer3 = bridge::getAddressFromPublicKeyTest(&pk3);

        assert!(bridge::get_quorum(&bridge) == INITIAL_QUORUM, 0);
        assert!(bridge::is_relayer(&bridge, relayer1), 2);
        assert!(bridge::is_relayer(&bridge, relayer2), 3);
        assert!(bridge::is_relayer(&bridge, relayer3), 4);
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
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
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
fun test_set_quorum_success() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3, PK4];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        bridge::set_quorum(&mut bridge, &safe, 4, ts::ctx(&mut scenario));
        assert!(bridge::get_quorum(&bridge) == 4, 0);

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)] //0
fun test_set_quorum_not_admin() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(USER);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut bridge = ts::take_shared<Bridge>(&scenario);

        bridge::set_quorum(&mut bridge, &safe, 4, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_add_relayer_success() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        assert!(bridge::get_relayer_count(&bridge) == 3, 1);

        bridge::add_relayer(&mut bridge, &safe, PK4, ts::ctx(&mut scenario));

        assert!(bridge::get_relayer_count(&bridge) == 4, 3);

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_remove_relayer_success() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3, PK4];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        let pk4 = PK4;
        let relayer4 = bridge::getAddressFromPublicKeyTest(&pk4);

        assert!(bridge::is_relayer(&bridge, relayer4), 0);
        assert!(bridge::get_relayer_count(&bridge) == 4, 1);

        bridge::remove_relayer(&mut bridge, &safe, relayer4, ts::ctx(&mut scenario));

        assert!(!bridge::is_relayer(&bridge, relayer4), 2);
        assert!(bridge::get_relayer_count(&bridge) == 3, 3);

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ECannotRemoveRelayerBelowQuorum)]
fun test_remove_relayer_below_quorum() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        bridge::remove_relayer(&mut bridge, &safe, RELAYER3, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_pause_unpause_contract() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        let pause = bridge::get_pause(&bridge);
        assert!(!pause, 0);

        bridge::pause_contract(&mut bridge, &safe, ts::ctx(&mut scenario));

        let pause = bridge::get_pause(&bridge);
        assert!(pause, 1);

        bridge::unpause_contract(&mut bridge, &safe, ts::ctx(&mut scenario));

        let pause = bridge::get_pause(&bridge);
        assert!(!pause, 2);

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_getter_functions() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Compute actual relayer addresses from public keys
        let pk1 = PK1;
        let pk2 = PK2;
        let pk3 = PK3;
        let relayer1 = bridge::getAddressFromPublicKeyTest(&pk1);
        let relayer2 = bridge::getAddressFromPublicKeyTest(&pk2);
        let relayer3 = bridge::getAddressFromPublicKeyTest(&pk3);

        assert!(bridge::get_quorum(&bridge) == INITIAL_QUORUM, 0);
        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == 10 * 1000, 2);
        assert!(bridge::get_relayer_count(&bridge) == 3, 3);

        assert!(bridge::is_relayer(&bridge, relayer1), 4);
        assert!(bridge::is_relayer(&bridge, relayer2), 5);
        assert!(bridge::is_relayer(&bridge, relayer3), 6);
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
fun test_set_batch_settle_timeout_success() {
    let mut scenario = setup();
    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        bridge::pause_contract(&mut bridge, &safe, ts::ctx(&mut scenario));

        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == 10 * 1000, 0);

        let new_timeout = 30 * 60 * 1000; // 30 minutes
        bridge::set_batch_settle_timeout_ms(
            &mut bridge,
            &safe,
            new_timeout,
            &clock,
            ts::ctx(&mut scenario),
        );

        assert!(bridge::get_batch_settle_timeout_ms(&bridge) == new_timeout, 1);

        ts::return_shared(bridge);
        ts::return_shared(safe);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_set_batch_settle_timeout_not_admin() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        bridge::set_batch_settle_timeout_ms(
            &mut bridge,
            &safe,
            30 * 60 * 1000,
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
fun test_execute_transfer_invalid_signature_length() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    // Compute actual relayer address from the first public key
    let pk1 = PK1;
    let relayer1 = bridge::getAddressFromPublicKeyTest(&pk1);

    scenario.next_tx(relayer1);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<lkt::Treasury<BRIDGE_TOKEN>>();
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let recipients = vector[USER];
        let amounts = vector[1000];
        let deposit_nonces = vector[1];
        let tokens = utils::type_name_bytes<TEST_COIN>();
        let batch_nonce_mvx = 1;

        let invalid_signatures = vector[b"short", b"too_short", b"also_short"];

        bridge::execute_transfer<TEST_COIN>(
            &mut bridge,
            &mut safe,
            recipients,
            amounts,
            tokens,
            deposit_nonces,
            batch_nonce_mvx,
            invalid_signatures,
            false,
            &mut treasury,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(bridge);
        ts::return_shared(treasury);
        ts::return_shared(safe);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EQuorumNotReached)]
fun test_execute_transfer_insufficient_signatures() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    // Compute actual relayer address from the first public key
    let pk1 = PK1;
    let relayer1 = bridge::getAddressFromPublicKeyTest(&pk1);

    scenario.next_tx(relayer1);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<lkt::Treasury<BRIDGE_TOKEN>>();
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let recipients = vector[USER];
        let amounts = vector[1000];
        let deposit_nonces = vector[1];
        let batch_nonce_mvx = 1;
        let token = utils::type_name_bytes<TEST_COIN>();

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
            token,
            deposit_nonces,
            batch_nonce_mvx,
            signatures,
            false,
            &mut treasury,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(bridge);
        ts::return_shared(safe);
        ts::return_shared(treasury);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EInvalidPublicKeyLength)]
fun test_add_relayer_invalid_public_key_length() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        let invalid_pk = b"too_short_key";
        bridge::add_relayer(&mut bridge, &safe, invalid_pk, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_add_relayer_not_admin() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        bridge::add_relayer(&mut bridge, &safe, PK4, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_remove_relayer_not_admin() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3, PK4];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        bridge::remove_relayer(&mut bridge, &safe, RELAYER4, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_pause_contract_not_admin() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        bridge::pause_contract(&mut bridge, &safe, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = ESenderNotActiveRole)]
fun test_unpause_contract_not_admin() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    scenario.next_tx(ADMIN);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        bridge::pause_contract(&mut bridge, &safe, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    scenario.next_tx(USER); // Switch to non-admin
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let safe = ts::take_shared<BridgeSafe>(&scenario);

        bridge::unpause_contract(&mut bridge, &safe, ts::ctx(&mut scenario));

        ts::return_shared(bridge);
        ts::return_shared(safe);
    };

    ts::end(scenario);
}

#[test]
fun test_getAddressFromPublicKey() {
    let public_key = x"dd7573d5a4b186828d40b187a804d952feb384f5b6b0f3c7472855a2cbdba506";
    let expected_address = @0xd5468a8e8d62b71214cdddb2ad421eefa462a672e2d5d0f89e99d8bf78e55769;

    let computed_address = bridge::getAddressFromPublicKeyTest(&public_key);

    let computed_bytes = sui::address::to_bytes(computed_address);
    let expected_bytes = sui::address::to_bytes(expected_address);

    std::debug::print(&b"Computed address bytes:");
    std::debug::print(&computed_bytes);

    std::debug::print(&b"Expected address bytes:");
    std::debug::print(&expected_bytes);

    assert!(vector::length(&computed_bytes) == vector::length(&expected_bytes), 1);

    assert!(computed_address == expected_address, 0);
}

#[test]
#[expected_failure(abort_code = bridge::EInvalidTypeArgument)]
fun test_execute_transfer_invalid_type_argument() {
    let mut scenario = setup();

    scenario.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&scenario);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false, // is_locked
            ts::ctx(&mut scenario),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(safe);
    };

    // Compute actual relayer address from the first public key
    let pk1 = PK1;
    let relayer1_bytes = sui::hash::blake2b256(&pk1);
    let relayer1 = sui::address::from_bytes(relayer1_bytes);

    scenario.next_tx(relayer1);
    {
        let mut bridge = ts::take_shared<Bridge>(&scenario);
        let mut safe = ts::take_shared<BridgeSafe>(&scenario);
        let mut treasury = scenario.take_shared<lkt::Treasury<BRIDGE_TOKEN>>();
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        let recipients = vector[USER];
        let amounts = vector[1000];
        let deposit_nonces = vector[1];
        let batch_nonce_mvx = 1;

        // Create a wrong token type name that doesn't match TEST_COIN type
        let wrong_token = b"0x2::coin::Coin<some_other_type>";

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
        let mut mock_sig3 = PK3;
        vector::append(
            &mut mock_sig3,
            b"ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210987654321098765432109876543",
        );

        let signatures = vector[mock_sig1, mock_sig2, mock_sig3];

        // This should fail with EInvalidTypeArgument because wrong_token != TEST_COIN type name
        bridge::execute_transfer<TEST_COIN>(
            &mut bridge,
            &mut safe,
            recipients,
            amounts,
            wrong_token,
            deposit_nonces,
            batch_nonce_mvx,
            signatures,
            false,
            &mut treasury,
            &clock,
            ts::ctx(&mut scenario),
        );

        ts::return_shared(bridge);
        ts::return_shared(safe);
        ts::return_shared(treasury);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario);
}
