#[test_only]
module bridge_safe::bridge_roles_tests;

use bridge_safe::bridge_roles::{Self, BridgeCap, BridgeSafeTag};
use sui::test_scenario::{Self as ts};
use sui_extensions::two_step_role;

const ADMIN: address = @0xa11ce;
const NEW_ADMIN: address = @0xb0b;
const INVALID_ADDRESS: address = @0x0;

#[test]
fun test_new_roles() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let roles = bridge_roles::new<BridgeSafeTag>(ADMIN, scenario.ctx());
        
        // Verify the owner is set correctly
        assert!(bridge_roles::owner(&roles) == ADMIN, 0);
        
        // Verify there's no pending owner initially
        assert!(bridge_roles::pending_owner(&roles).is_none(), 1);
        
        // Since Roles doesn't have key ability, we just drop it
        sui::test_utils::destroy(roles);
    };
    
    ts::end(scenario);
}

#[test]
fun test_owner_functions() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let roles = bridge_roles::new<BridgeSafeTag>(ADMIN, scenario.ctx());
        
        // Test owner getter
        assert!(bridge_roles::owner(&roles) == ADMIN, 0);
        
        // Test pending_owner getter (should be none initially)
        let pending = bridge_roles::pending_owner(&roles);
        assert!(pending.is_none(), 1);
        
        sui::test_utils::destroy(roles);
    };
    
    ts::end(scenario);
}

#[test]
fun test_grant_witness() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test granting witness - witness has drop ability so this should work
        let _witness = bridge_roles::grant_witness();
        // Witness is automatically dropped
    };
    
    ts::end(scenario);
}

#[test]
fun test_publish_caps() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test publishing capabilities
        let witness = bridge_roles::grant_witness();
        let bridge_cap = bridge_roles::publish_caps(witness, scenario.ctx());
        
        // BridgeCap should be created successfully
        // Transfer it to admin for cleanup
        transfer::public_transfer(bridge_cap, ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
fun test_transfer_bridge_capability() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let witness = bridge_roles::grant_witness();
        let bridge_cap = bridge_roles::publish_caps(witness, scenario.ctx());
        
        // Test transferring bridge capability to a valid address
        bridge_roles::transfer_bridge_capability(bridge_cap, NEW_ADMIN);
    };
    
    // Verify the capability was transferred
    scenario.next_tx(NEW_ADMIN);
    {
        let bridge_cap = scenario.take_from_address<BridgeCap>(NEW_ADMIN);
        transfer::public_transfer(bridge_cap, NEW_ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 0)]
fun test_transfer_bridge_capability_to_zero_address() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let witness = bridge_roles::grant_witness();
        let bridge_cap = bridge_roles::publish_caps(witness, scenario.ctx());
        
        // This should fail because we're trying to transfer to zero address
        bridge_roles::transfer_bridge_capability(bridge_cap, INVALID_ADDRESS);
    };
    
    ts::end(scenario);
}

#[test]
fun test_owner_role_access() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let mut roles = bridge_roles::new<BridgeSafeTag>(ADMIN, scenario.ctx());
        
        // Test immutable access to owner role
        let owner_role = bridge_roles::owner_role(&roles);
        assert!(two_step_role::active_address(owner_role) == ADMIN, 0);
        assert!(two_step_role::pending_address(owner_role).is_none(), 1);
        
        // Test mutable access to owner role
        let owner_role_mut = bridge_roles::owner_role_mut(&mut roles);
        assert!(two_step_role::active_address(owner_role_mut) == ADMIN, 2);
        
        sui::test_utils::destroy(roles);
    };
    
    ts::end(scenario);
}

#[test]
fun test_two_step_role_transfer_initiate() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let mut roles = bridge_roles::new<BridgeSafeTag>(ADMIN, scenario.ctx());
        
        // Initiate transfer to new admin
        let owner_role_mut = bridge_roles::owner_role_mut(&mut roles);
        two_step_role::begin_role_transfer(owner_role_mut, NEW_ADMIN, scenario.ctx());
        
        // Verify the transfer was initiated
        assert!(bridge_roles::owner(&roles) == ADMIN, 0); // Still the current owner  
        assert!(bridge_roles::pending_owner(&roles).is_some(), 1); // Has pending owner
        assert!(*bridge_roles::pending_owner(&roles).borrow() == NEW_ADMIN, 2);
        
        sui::test_utils::destroy(roles);
    };
    
    ts::end(scenario);
}

#[test]
fun test_multiple_roles_instances() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Create multiple roles instances
        let roles1 = bridge_roles::new<BridgeSafeTag>(ADMIN, scenario.ctx());
        let roles2 = bridge_roles::new<BridgeSafeTag>(NEW_ADMIN, scenario.ctx());
        
        // Verify they have different owners
        assert!(bridge_roles::owner(&roles1) == ADMIN, 0);
        assert!(bridge_roles::owner(&roles2) == NEW_ADMIN, 1);
        
        // Both should have no pending owners initially
        assert!(bridge_roles::pending_owner(&roles1).is_none(), 2);
        assert!(bridge_roles::pending_owner(&roles2).is_none(), 3);
        
        sui::test_utils::destroy(roles1);
        sui::test_utils::destroy(roles2);
    };
    
    ts::end(scenario);
}

#[test]
fun test_bridge_cap_properties() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let witness = bridge_roles::grant_witness();
        let bridge_cap = bridge_roles::publish_caps(witness, scenario.ctx());
        
        // BridgeCap should have key and store abilities
        // We can transfer it, which tests both key and store
        transfer::public_transfer(bridge_cap, ADMIN);
    };
    
    scenario.next_tx(ADMIN);
    {
        // Should be able to take it back, confirming it has proper abilities
        let bridge_cap = scenario.take_from_address<BridgeCap>(ADMIN);
        transfer::public_transfer(bridge_cap, ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
fun test_witness_usage_pattern() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let witness1 = bridge_roles::grant_witness();
        let witness2 = bridge_roles::grant_witness();
        
        let cap1 = bridge_roles::publish_caps(witness1, scenario.ctx());
        let cap2 = bridge_roles::publish_caps(witness2, scenario.ctx());
        
        transfer::public_transfer(cap1, ADMIN);
        transfer::public_transfer(cap2, ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
fun test_role_transfer_edge_cases() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        let mut roles = bridge_roles::new<BridgeSafeTag>(ADMIN, scenario.ctx());
        
        let owner_role_mut = bridge_roles::owner_role_mut(&mut roles);
        two_step_role::begin_role_transfer(owner_role_mut, ADMIN, scenario.ctx());
        
        assert!(bridge_roles::owner(&roles) == ADMIN, 0);
        assert!(bridge_roles::pending_owner(&roles).is_some(), 1);
        assert!(*bridge_roles::pending_owner(&roles).borrow() == ADMIN, 2);
        
        sui::test_utils::destroy(roles);
    };
    
    ts::end(scenario);
}