#[test_only]
module bridge_safe::bridge_comprehensive_tests;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::safe::{Self, BridgeSafe};
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

fun setup_bridge_with_relayers_for_quorum(): (Scenario, vector<vector<u8>>, vector<address>) {
    let mut scenario = ts::begin(ADMIN);
    
    let pk1 = x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    let pk2 = x"abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
    let pk3 = x"fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321";
    let pk4 = x"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    
    let public_keys = vector[pk1, pk2, pk3, pk4];
    
    let addr1 = bridge::getAddressFromPublicKeyTest(&pk1);
    let addr2 = bridge::getAddressFromPublicKeyTest(&pk2);
    let addr3 = bridge::getAddressFromPublicKeyTest(&pk3);
    let addr4 = bridge::getAddressFromPublicKeyTest(&pk4);
    
    let relayer_addresses = vector[addr1, addr2, addr3, addr4];
    
    br::init_for_testing(scenario.ctx());
    
    scenario.next_tx(ADMIN);
    {
        let mut treasury = scenario.take_shared<Treasury<BRIDGE_TOKEN>>();
        lkt::transfer_to_coin_cap<BRIDGE_TOKEN>(&mut treasury, ADMIN, scenario.ctx());
        lkt::transfer_from_coin_cap<BRIDGE_TOKEN>(&mut treasury, ADMIN, scenario.ctx());
        ts::return_shared(treasury);
    };

    scenario.next_tx(ADMIN);
    {
        let from_cap_db = scenario.take_from_address<FromCoinCap<BRIDGE_TOKEN>>(ADMIN);
        safe::init_for_testing(from_cap_db, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        let safe = scenario.take_shared<BridgeSafe>();
        let bridge_cap = scenario.take_from_address<BridgeCap>(ADMIN);
        
        bridge::initialize(
            public_keys,
            3, 
            object::id_address(&safe),
            bridge_cap,
            scenario.ctx()
        );
        
        ts::return_shared(safe);
    };
    
    (scenario, public_keys, relayer_addresses)
}

fun create_test_signature_for_quorum(public_key: &vector<u8>): vector<u8> {
    let mut signature = vector::empty<u8>();
    
    let mut i = 0;
    while (i < 64) {
        vector::push_back(&mut signature, (i % 256) as u8);
        i = i + 1;
    };
    
    vector::append(&mut signature, *public_key);
    
    signature
}

#[test]
#[expected_failure(abort_code = bridge::EInvalidSignature)] // Expecting failure at signature verification
fun test_validate_quorum_reaches_signature_verification() {
    let (mut scenario, public_keys, _relayer_addresses) = setup_bridge_with_relayers_for_quorum();
    
    scenario.next_tx(ADMIN);
    {
        let bridge = scenario.take_shared<Bridge>();
        
        // Create test data
        let batch_id = 1u64;
        let recipients = vector[@0x123, @0x456, @0x789];
        let amounts = vector[100u64, 200u64, 300u64];
        let deposit_nonces = vector[1u64, 2u64, 3u64];
        
        // Create signatures for 3 out of 4 relayers (meeting quorum of 3)
        // These will have correct format but invalid cryptographic signatures
        let mut signatures = vector::empty<vector<u8>>();
        vector::push_back(&mut signatures, create_test_signature_for_quorum(vector::borrow(&public_keys, 0)));
        vector::push_back(&mut signatures, create_test_signature_for_quorum(vector::borrow(&public_keys, 1)));
        vector::push_back(&mut signatures, create_test_signature_for_quorum(vector::borrow(&public_keys, 2)));
        
        // This should fail at signature verification (proving we got through initial checks)
        bridge::validate_quorum_for_testing<TEST_COIN>(
            &bridge,
            batch_id,
            &recipients,
            &amounts,
            &signatures,
            &deposit_nonces
        );
        
        ts::return_shared(bridge);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EQuorumNotReached)]
fun test_validate_quorum_insufficient_signatures() {
    let (mut scenario, public_keys, _relayer_addresses) = setup_bridge_with_relayers_for_quorum();
    
    scenario.next_tx(ADMIN);
    {
        let bridge = scenario.take_shared<Bridge>();
        
        // Create test data
        let batch_id = 1u64;
        let recipients = vector[@0x123, @0x456];
        let amounts = vector[100u64, 200u64];
        let deposit_nonces = vector[1u64, 2u64];
        
        // Create signatures for only 2 out of 4 relayers (below quorum of 3)
        let mut signatures = vector::empty<vector<u8>>();
        vector::push_back(&mut signatures, create_test_signature_for_quorum(vector::borrow(&public_keys, 0)));
        vector::push_back(&mut signatures, create_test_signature_for_quorum(vector::borrow(&public_keys, 1)));
        
        // This should fail as we have fewer signatures than quorum
        bridge::validate_quorum_for_testing<TEST_COIN>(
            &bridge,
            batch_id,
            &recipients,
            &amounts,
            &signatures,
            &deposit_nonces
        );
        
        ts::return_shared(bridge);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::EInvalidSignatureLength)]
fun test_validate_quorum_invalid_signature_length() {
    let (mut scenario, _public_keys, _relayer_addresses) = setup_bridge_with_relayers_for_quorum();
    
    scenario.next_tx(ADMIN);
    {
        let bridge = scenario.take_shared<Bridge>();
        
        // Create test data
        let batch_id = 1u64;
        let recipients = vector[@0x123];
        let amounts = vector[100u64];
        let deposit_nonces = vector[1u64];
        
        // Create signatures with invalid length (should be 96 bytes)
        let mut signatures = vector::empty<vector<u8>>();
        let invalid_signature = vector[1u8, 2u8, 3u8]; // Only 3 bytes instead of 96
        vector::push_back(&mut signatures, invalid_signature);
        vector::push_back(&mut signatures, invalid_signature);
        vector::push_back(&mut signatures, invalid_signature);
        
        // This should fail due to invalid signature length
        bridge::validate_quorum_for_testing<TEST_COIN>(
            &bridge,
            batch_id,
            &recipients,
            &amounts,
            &signatures,
            &deposit_nonces
        );
        
        ts::return_shared(bridge);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bridge::ERelayerNotFound)]
fun test_validate_quorum_unknown_relayer() {
    let (mut scenario, _public_keys, _relayer_addresses) = setup_bridge_with_relayers_for_quorum();
    
    scenario.next_tx(ADMIN);
    {
        let bridge = scenario.take_shared<Bridge>();
        
        // Create test data
        let batch_id = 1u64;
        let recipients = vector[@0x123];
        let amounts = vector[100u64];
        let deposit_nonces = vector[1u64];
        
        // Create signatures with unknown public keys (not in relayer list)
        let unknown_pk = x"9999999999999999999999999999999999999999999999999999999999999999";
        let mut signatures = vector::empty<vector<u8>>();
        vector::push_back(&mut signatures, create_test_signature_for_quorum(&unknown_pk));
        vector::push_back(&mut signatures, create_test_signature_for_quorum(&unknown_pk));
        vector::push_back(&mut signatures, create_test_signature_for_quorum(&unknown_pk));
        
        // This should fail because the public key is not from a known relayer
        bridge::validate_quorum_for_testing<TEST_COIN>(
            &bridge,
            batch_id,
            &recipients,
            &amounts,
            &signatures,
            &deposit_nonces
        );
        
        ts::return_shared(bridge);
    };
    
    ts::end(scenario);
}
