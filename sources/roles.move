module bridge_safe::bridge_roles;

use sui::bag::{Self, Bag};
use sui_extensions::two_step_role::{Self, TwoStepRole};

// Unique phantom tag to namespace these roles to your package/object
public struct BridgeSafeTag has drop {}

/// Stores the admin role as a TwoStepRole
public struct Roles<phantom T> has store {
    /// A bag that maintains the mapping of privileged roles and their addresses.
    /// Keys are structs that are suffixed with _Key.
    /// Values are either addresses or objects containing more complex logic.
    data: Bag,
}

/// Type used to specify which TwoStepRole the owner role corresponds to.
public struct OwnerRole<phantom T> has drop {}

/// Key used to map to the mutable TwoStepRole of the owner EOA
public struct OwnerKey {} has copy, drop, store;

public struct BridgeCap has key, store {
    id: UID,
}

public struct BridgeWitness has drop {}

public(package) fun grant_witness(): BridgeWitness { BridgeWitness {} }

public(package) fun publish_caps(_w: BridgeWitness, ctx: &mut TxContext): (BridgeCap) {
    (BridgeCap { id: object::new(ctx) })
}

public(package) fun transfer_bridge_capability(
    bridge_cap: BridgeCap,
    new_bridge: address,
) {
    assert!(new_bridge != @0x0, 0);
    transfer::public_transfer(bridge_cap, new_bridge);
}

/// Events for admin role transfer
public(package) fun owner_role_mut<T>(roles: &mut Roles<T>): &mut TwoStepRole<OwnerRole<T>> {
    roles.data.borrow_mut(OwnerKey {})
}

/// [Package private] Gets an immutable reference to the owner's TwoStepRole object.
public(package) fun owner_role<T>(roles: &Roles<T>): &TwoStepRole<OwnerRole<T>> {
    roles.data.borrow(OwnerKey {})
}

/// Gets the current owner address.
public fun owner<T>(roles: &Roles<T>): address {
    roles.owner_role().active_address()
}

/// Gets the pending owner address.
public fun pending_owner<T>(roles: &Roles<T>): Option<address> {
    roles.owner_role().pending_address()
}

public(package) fun new<T>(
    owner: address,
    ctx: &mut TxContext,
): Roles<T> {
    let mut data = bag::new(ctx);
    data.add(OwnerKey {}, two_step_role::new(OwnerRole<T> {}, owner));
    Roles {
        data,
    }
}
