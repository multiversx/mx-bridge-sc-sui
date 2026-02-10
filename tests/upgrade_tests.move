#[test_only]
module bridge_safe::upgrade_tests;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::safe::{Self, BridgeSafe};
use bridge_safe::upgrade_manager;
use bridge_safe::bridge_version_control;
use locked_token::bridge_token::{Self as br, BRIDGE_TOKEN};
use locked_token::treasury::{Self as lkt, Treasury, FromCoinCap};
use sui::test_scenario::{Self as ts, Scenario};

public struct TEST_COIN has drop {}

const ADMIN: address = @0xa11ce;

const INITIAL_QUORUM: u64 = 3;
const MIN_AMOUNT: u64 = 100;
const MAX_AMOUNT: u64 = 1000000;

const PK1: vector<u8> = b"12345678901234567890123456789012";
const PK2: vector<u8> = b"abcdefghijklmnopqrstuvwxyz123456";
const PK3: vector<u8> = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";

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

    s.next_tx(ADMIN);
    {
        let mut safe = ts::take_shared<BridgeSafe>(&s);
        let bridge_cap = ts::take_from_sender<BridgeCap>(&s);

        safe::whitelist_token<TEST_COIN>(
            &mut safe,
            MIN_AMOUNT,
            MAX_AMOUNT,
            true,
            false,
            s.ctx(),
        );

        let public_keys = vector[PK1, PK2, PK3];

        bridge::initialize(
            public_keys,
            INITIAL_QUORUM,
            object::id_address(&safe),
            bridge_cap,
            s.ctx(),
        );

        ts::return_shared(safe);
    };

    s
}

#[test]
fun test_upgrade_workflow() {
    let mut scenario = setup();
    
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge = ts::take_shared<Bridge>(&scenario);
        
        // Check initial versions
        let safe_versions = safe::compatible_versions(&safe);
        let bridge_versions = bridge::bridge_compatible_versions(&bridge);
        
        assert!(safe_versions.length() == 1, 0);
        assert!(bridge_versions.length() == 1, 1);
        assert!(safe_versions[0] == bridge_version_control::current_version(), 2);
        assert!(bridge_versions[0] == bridge_version_control::current_version(), 3);
        
        // Check that no migration is in progress
        assert!(!safe::is_migration_in_progress(&safe), 4);
        assert!(!bridge::is_bridge_migration_in_progress(&bridge), 5);
        assert!(!upgrade_manager::is_system_migration_in_progress(&safe, &bridge), 6);
        
        ts::return_shared(safe);
        ts::return_shared(bridge);
    };
    
    ts::end(scenario);
}

#[test]
fun test_system_upgrade_status() {
    let mut scenario = setup();
    
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge = ts::take_shared<Bridge>(&scenario);
        
        // Test version functions
        let safe_active = safe::current_active_version(&safe);
        let bridge_active = bridge::bridge_current_active_version(&bridge);
        
        assert!(safe_active == bridge_version_control::current_version(), 4);
        assert!(bridge_active == bridge_version_control::current_version(), 5);
        
        // Test pending versions (should be none)
        let safe_pending = safe::pending_version(&safe);
        let bridge_pending = bridge::bridge_pending_version(&bridge);
        
        assert!(safe_pending.is_none(), 6);
        assert!(bridge_pending.is_none(), 7);
        
        ts::return_shared(safe);
        ts::return_shared(bridge);
    };
    
    ts::end(scenario);
}

#[test]
fun test_compatibility_assertions() {
    let mut scenario = setup();
    
    scenario.next_tx(ADMIN);
    {
        let safe = ts::take_shared<BridgeSafe>(&scenario);
        let bridge = ts::take_shared<Bridge>(&scenario);
        
        // These should not abort since objects are compatible
        safe::assert_is_compatible(&safe);
        bridge::assert_bridge_is_compatible(&bridge);
        
        ts::return_shared(safe);
        ts::return_shared(bridge);
    };
    
    ts::end(scenario);
}
