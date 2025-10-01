module locked_token::lk_roles;

use sui::bag::{Self, Bag};
use sui_extensions::two_step_role::{Self, TwoStepRole};

public struct Roles<phantom T> has store {
    // holds mapping of the roles, floxible to add more
    data: Bag
}

/// Type used to specify which TwoStepRole the owner role corresponds to.
public struct OwnerRole<phantom T> has drop {}

/// The key used to map to the TwoStepRole of the owner EOA
public struct OwnerKey {} has copy, store, drop;

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
        data
    }
}
