module locked_token::treasury;

use sui::coin::{Self, TreasuryCap};
use sui::token::{Self as t, Token, TokenPolicyCap};
use sui::dynamic_object_field as dof;
use sui::event;
use sui::table::{Self as table, Table};

use locked_token::lk_roles::{Self, Roles};

const ENotOwner: u64 = 1;
const ECapNotAuthorized: u64 = 2;
const EAuthorizationDoesNotExist: u64 = 3;

/// Key for retrieving the `TreasuryCap` stored in a `Treasury<T>` dynamic object field
public struct TreasuryCapKey has copy, store, drop {}
/// Key for retrieving the `PolicyCap` stored in a `Treasury<T>` dynamic object field
public struct PolicyCapKey has copy, store, drop {}

/// Object representing the right for an admin or object to perform to_coin over the Token object
public struct ToCoinCap<phantom T> has key, store {
    id: UID,
}

/// Object representing the right for an admin or object to perform from_coin over the Token object
public struct FromCoinCap<phantom T> has key, store {
    id: UID,
}

/* ================== Events ============================ */

/// Event emitted when creating a ToCoinCap object
public struct ToCoinCapCreated<phantom T> has copy, drop {
    to_coin_cap: ID
}

/// Event emitted when creating a FromCoinCap object
public struct FromCoinCapCreated<phantom T> has copy, drop {
    from_coin_cap: ID
}

/// Responsible for handling of token capabilities and policies
public struct Treasury<phantom T> has key, store {
    id: UID,

    roles: Roles<T>,
    active_authorizations: Table<ID, bool>,
}

public fun new<T>(
    treasury_cap: TreasuryCap<T>,
    policy_cap: TokenPolicyCap<T>,
    owner: address,
    ctx: &mut TxContext
): Treasury<T> {
    let roles = lk_roles::new(owner, ctx);
    let mut treasury = Treasury {
        id: object::new(ctx),
        roles,
        active_authorizations: table::new(ctx),
    };

    dof::add(&mut treasury.id, TreasuryCapKey {}, treasury_cap);
    dof::add(&mut treasury.id, PolicyCapKey {}, policy_cap);
    treasury
}

/* ================= Owner only ============================ */

/// Create a FromCoinCap object and send it to required address
public fun transfer_from_coin_cap<T>(
    treasury: &mut Treasury<T>,
    receiver: address,
    ctx: &mut TxContext
) {
    let cap = create_from_coin_cap(treasury, ctx);
    transfer::transfer(cap, receiver);
}

/// Composable entry that creates a new FromCoinCap and returns it
fun create_from_coin_cap<T>(
    treasury: &mut Treasury<T>, 
    ctx: &mut TxContext
): FromCoinCap<T> {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);

    let from_coin_cap = FromCoinCap { id: object::new(ctx) };
    table::add(&mut treasury.active_authorizations, object::id(&from_coin_cap), true);
    event::emit(FromCoinCapCreated<T> { 
        from_coin_cap: object::id(&from_coin_cap)
    });

    from_coin_cap
}

/// Create a ToCoinCap object and send it to required address
public fun transfer_to_coin_cap<T>(
    treasury: &mut Treasury<T>,
    receiver: address,
    ctx: &mut TxContext
) {
    let cap = create_to_coin_cap(treasury, ctx);
    transfer::transfer(cap, receiver);
}

/// Composable entry that creates a new ToCoinCap and returns it
fun create_to_coin_cap<T>(
    treasury: &mut Treasury<T>, 
    ctx: &mut TxContext
): ToCoinCap<T> {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);

    let to_coin_cap = ToCoinCap { id: object::new(ctx) };
    table::add(&mut treasury.active_authorizations, object::id(&to_coin_cap), true);
    event::emit(ToCoinCapCreated<T> { 
        to_coin_cap: object::id(&to_coin_cap)
    });

    to_coin_cap
}

/// Revokes a previously created cap's rights to use from_coin and to_coin
public fun revoke_authorization<T>(
    treasury: &mut Treasury<T>,
    cap_id: ID,
    ctx: &mut TxContext
) {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);
    assert!(table::contains(&treasury.active_authorizations, cap_id), EAuthorizationDoesNotExist);

    let _ = table::remove(&mut treasury.active_authorizations, cap_id); 
}

public fun mint_coin_to_receiver<T>(
    treasury: &mut Treasury<T>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);
    let tcap = treasury_mut_cap_ref(treasury);

    tcap.mint_and_transfer<T>(amount, recipient, ctx)
}

public fun transfer_ownership<T>(treasury: &mut Treasury<T>, new_owner: address, ctx: &TxContext) {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);

    treasury.roles.owner_role_mut().begin_role_transfer(new_owner, ctx)
}


public fun accept_ownership<T>(treasury: &mut Treasury<T>, ctx: &TxContext) {
    let pending = treasury.roles.pending_owner();

    assert!(option::is_some(&pending) && option::borrow(&pending) == ctx.sender(), ENotOwner);

    treasury.roles.owner_role_mut().accept_role(ctx)
}

/*======================= Access control ===============================*/

public fun assert_active_auth<T>(treasury: &Treasury<T>, id: ID) {
    assert!(table::contains(&treasury.active_authorizations, id) && *table::borrow(&treasury.active_authorizations, id), ECapNotAuthorized);
}

/*====================== User facing ==================================*/

/// Checks for a valid ToCoinCap and unwraps the Coin object from the input Token
public fun to_coin<T>(
    treasury: &Treasury<T>,
    to_coin_cap: &ToCoinCap<T>,
    input_token: Token<T>,
    ctx: &mut TxContext
): coin::Coin<T> {
    assert_active_auth(treasury, object::id(to_coin_cap));
    let (out, mut request) = t::to_coin(input_token, ctx);

    let policy = policy_cap_ref(treasury);
    t::confirm_with_policy_cap(policy, request, ctx);

    out
}

/// Checks for a valid FromCoinCap and wrapps a Coin into a Token
public fun from_coin<T>(
    treasury: &Treasury<T>,
    from_coin_cap: &FromCoinCap<T>,
    input_coin: coin::Coin<T>,
    ctx: &mut TxContext
): Token<T> {
    assert_active_auth(treasury, object::id(from_coin_cap));
    let (out, request) = t::from_coin(input_coin, ctx);

    let policy = policy_cap_ref(treasury);
    t::confirm_with_policy_cap(policy, request, ctx);
    
    out
}

/// Wraps a Coin into a Token and transfers it to the recipient. Only FromCoin cap holders can use this
public fun transfer_from_coin<T>(
    treasury: &mut Treasury<T>,
    recipient: address,
    from_coin_cap: &FromCoinCap<T>,
    input_coin: coin::Coin<T>,
    ctx: &mut TxContext
) {
    let wrapped_token = from_coin(treasury, from_coin_cap, input_coin, ctx);

    let policy = policy_cap_ref(treasury);
    let request = t::transfer(wrapped_token, recipient, ctx);
    t::confirm_with_policy_cap(policy, request, ctx);
}

/*==================== Internals ======================================*/
fun policy_cap_ref<T>(t: &Treasury<T>): &TokenPolicyCap<T> {
    dof::borrow(&t.id, PolicyCapKey {})
}

fun treasury_cap_ref<T>(t: &Treasury<T>): &TreasuryCap<T> {
    dof::borrow(&t.id, TreasuryCapKey {})
}

fun treasury_mut_cap_ref<T>(t: &mut Treasury<T>): &mut TreasuryCap<T> {
    dof::borrow_mut(&mut t.id, TreasuryCapKey {})
}
