/// Mint-burn adapter for the stablecoin-sui treasury (MintCap<T> mechanism).
///
/// Owns the full mint-burn deposit and transfer entry points. Stores a MintCap<T>
/// inside BridgeSafe's dynamic object fields and calls the treasury's burn/mint.
/// Adding a new mint-burn mechanism means adding a sibling adapter module here
/// with its own entry points — safe.move stays mechanism-agnostic.
module bridge_safe::xmn_mint_cap_adapter;

use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::events;
use bridge_safe::safe::{Self, BridgeSafe};
use bridge_safe::utils;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::deny_list::DenyList;
use sui::dynamic_object_field as dof;
use sui::object::UID;
use sui::transfer;
use sui::tx_context;
use treasury::treasury::{Self as stablecoin_treasury, MintCap, Treasury as XmnTreasury};

// DOF key — scoped to this module so it can't clash with other adapters.
public struct CapKey has copy, drop, store {
    token_type: vector<u8>,
}

const EMintBurnCapNotFound: u64 = 20;
const EMintBurnCapAlreadyRegistered: u64 = 21;

// === Internal helpers ===

fun cap_key<T>(): CapKey {
    CapKey { token_type: utils::type_name_bytes<T>() }
}

// === Low-level UID-based operations (package-internal) ===

public(package) fun register<T>(id: &mut UID, cap: MintCap<T>) {
    dof::add(id, cap_key<T>(), cap);
}

#[allow(lint(self_transfer))]
public(package) fun deregister<T>(id: &mut UID, recipient: address) {
    let cap = dof::remove<CapKey, MintCap<T>>(id, cap_key<T>());
    transfer::public_transfer(cap, recipient);
}

public(package) fun has_cap<T>(id: &UID): bool {
    dof::exists_with_type<CapKey, MintCap<T>>(id, cap_key<T>())
}

public(package) fun burn<T>(
    id: &UID,
    xmn_treasury: &mut XmnTreasury<T>,
    deny_list: &DenyList,
    coin_in: Coin<T>,
    ctx: &TxContext,
) {
    let cap = dof::borrow(id, cap_key<T>());
    stablecoin_treasury::burn(xmn_treasury, cap, deny_list, coin_in, ctx);
}

public(package) fun mint<T>(
    id: &UID,
    xmn_treasury: &mut XmnTreasury<T>,
    deny_list: &DenyList,
    amount: u64,
    receiver: address,
    ctx: &mut TxContext,
) {
    let cap = dof::borrow(id, cap_key<T>());
    stablecoin_treasury::mint(xmn_treasury, cap, deny_list, amount, receiver, ctx);
}

// === High-level BridgeSafe-aware entry points ===

/// Register a MintCap<T> for a mint-burn token. Only callable by the safe owner.
public fun register_mint_burn_cap<T>(
    safe: &mut BridgeSafe,
    cap: MintCap<T>,
    ctx: &TxContext,
) {
    safe::checkOwnerRole(safe, ctx);
    let key = utils::type_name_bytes<T>();
    safe::assert_token_is_whitelisted(safe, key);
    safe::assert_token_is_mint_burn(safe, key);
    assert!(!has_cap<T>(safe::uid(safe)), EMintBurnCapAlreadyRegistered);
    register<T>(safe::uid_mut(safe), cap);
}

/// Remove a MintCap<T> — only allowed once the token is de-whitelisted.
public fun deregister_mint_burn_cap<T>(safe: &mut BridgeSafe, ctx: &TxContext) {
    safe::checkOwnerRole(safe, ctx);
    let key = utils::type_name_bytes<T>();
    safe::assert_token_is_not_whitelisted(safe, key);
    assert!(has_cap<T>(safe::uid(safe)), EMintBurnCapNotFound);
    deregister<T>(safe::uid_mut(safe), ctx.sender());
}

/// Deposit for mint-burn tokens: coin is burned immediately via the stablecoin-sui treasury.
public fun deposit_mint_burn<T>(
    safe: &mut BridgeSafe,
    coin_in: Coin<T>,
    recipient: vector<u8>,
    clock: &Clock,
    xmn_treasury: &mut XmnTreasury<T>,
    deny_list: &DenyList,
    ctx: &mut TxContext,
) {
    assert!(has_cap<T>(safe::uid(safe)), EMintBurnCapNotFound);

    let (key, amount, batch_nonce, dep_nonce) =
        safe::deposit_validate_and_record<T>(safe, &coin_in, recipient, true, clock, ctx);

    burn<T>(safe::uid(safe), xmn_treasury, deny_list, coin_in, ctx);

    events::emit_deposit(batch_nonce, dep_nonce, tx_context::sender(ctx), recipient, amount, key);
}

/// Transfer for mint-burn tokens: mints fresh coin to receiver via the stablecoin-sui treasury.
/// Only callable by the bridge role.
public(package) fun transfer_mint_burn<T>(
    safe: &mut BridgeSafe,
    _bridge_cap: &BridgeCap,
    receiver: address,
    amount: u64,
    xmn_treasury: &mut XmnTreasury<T>,
    deny_list: &DenyList,
    ctx: &mut TxContext,
): bool {
    if (!safe::has_token_config<T>(safe)) { return false };
    if (!safe::get_token_is_mint_burn<T>(safe)) { return false };
    if (safe::get_stored_coin_balance<T>(safe) < amount) { return false };
    if (!has_cap<T>(safe::uid(safe))) { return false };

    mint<T>(safe::uid(safe), xmn_treasury, deny_list, amount, receiver, ctx);
    safe::subtract_token_balance<T>(safe, amount);

    true
}
