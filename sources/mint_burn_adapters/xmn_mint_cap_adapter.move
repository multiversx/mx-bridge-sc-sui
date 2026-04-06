module bridge_safe::xmn_mint_cap_adapter;

use bridge_safe::bridge::Bridge;
use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::events;
use bridge_safe::safe::BridgeSafe;
use bridge_safe::utils;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::deny_list::DenyList;
use sui::dynamic_object_field as dof;
use treasury::treasury::{MintCap, Treasury as XmnTreasury};

public struct CapKey has copy, drop, store {
    token_type: vector<u8>,
}

const EMintBurnCapNotFound: u64 = 20;
const EMintBurnCapAlreadyRegistered: u64 = 21;

// === Public API ===

public fun deposit<T>(
    safe: &mut BridgeSafe,
    coin_in: Coin<T>,
    recipient: vector<u8>,
    clock: &Clock,
    xmn_treasury: &mut XmnTreasury<T>,
    deny_list: &DenyList,
    ctx: &mut TxContext,
) {
    safe.assert_is_compatible();
    assert!(has_cap<T>(safe.uid()), EMintBurnCapNotFound);

    let (key, amount, batch_nonce, dep_nonce) = safe.deposit_validate_and_record<T>(
        &coin_in,
        recipient,
        true,
        clock,
        ctx,
    );

    burn<T>(safe.uid(), xmn_treasury, deny_list, coin_in, ctx);

    events::emit_deposit_v1(
        batch_nonce,
        dep_nonce,
        ctx.sender(),
        recipient,
        amount,
        key,
    );
}

public fun execute_transfer<T>(
    bridge: &mut Bridge,
    safe: &mut BridgeSafe,
    recipients: vector<address>,
    amounts: vector<u64>,
    deposit_nonces: vector<u64>,
    batch_nonce_mvx: u64,
    signatures: vector<vector<u8>>,
    is_batch_complete: bool,
    xmn_treasury: &mut XmnTreasury<T>,
    deny_list: &DenyList,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bridge.assert_bridge_is_compatible();
    safe.assert_is_compatible();
    bridge.pre_execute_transfer<T>(
        batch_nonce_mvx,
        &recipients,
        &amounts,
        &deposit_nonces,
        &signatures,
        clock,
        ctx,
    );

    let len = recipients.length();
    let mut i = 0;
    while (i < len) {
        let success = transfer<T>(
            safe,
            bridge.bridge_cap(),
            *recipients.borrow(i),
            *amounts.borrow(i),
            xmn_treasury,
            deny_list,
            ctx,
        );
        bridge.record_transfer_result(batch_nonce_mvx, success);
        i = i + 1;
    };

    bridge.finalize_batch(batch_nonce_mvx, len, is_batch_complete, clock);
}

// === Admin Management ===

public fun whitelist_token<T>(
    safe: &mut BridgeSafe,
    minimum_amount: u64,
    maximum_amount: u64,
    cap: MintCap<T>,
    treasury_id: ID,
    ctx: &TxContext,
) {
    safe.assert_is_compatible();
    assert!(!has_cap<T>(safe.uid()), EMintBurnCapAlreadyRegistered);
    safe.whitelist_token_internal<T>(
        minimum_amount,
        maximum_amount,
        true,
        option::some(treasury_id),
        true,
        false,
        ctx,
    );
    register<T>(safe.uid_mut(), cap);
}

/// Remove a mint-burn token from the whitelist and deregister its MintCap in one atomic operation.
#[allow(lint(self_transfer))]
public fun remove_token_from_whitelist<T>(safe: &mut BridgeSafe, ctx: &mut TxContext) {
    safe.assert_is_compatible();
    safe.checkOwnerRole(ctx);
    assert!(has_cap<T>(safe.uid()), EMintBurnCapNotFound);
    deregister<T>(safe.uid_mut(), ctx.sender());
    let key = utils::type_name_bytes<T>();
    safe.unwhitelist_token(key);
}

// === Internal helpers ===

public(package) fun transfer<T>(
    safe: &mut BridgeSafe,
    _bridge_cap: &BridgeCap,
    receiver: address,
    amount: u64,
    xmn_treasury: &mut XmnTreasury<T>,
    deny_list: &DenyList,
    ctx: &mut TxContext,
): bool {
    if (!safe.has_token_config<T>()) { return false };
    if (!safe.get_token_is_mint_burn<T>()) { return false };
    if (safe.get_stored_coin_balance<T>() < amount) { return false };
    if (!has_cap<T>(safe.uid())) { return false };

    mint<T>(safe.uid(), xmn_treasury, deny_list, amount, receiver, ctx);
    safe.subtract_token_balance<T>(amount);

    true
}

fun cap_key<T>(): CapKey {
    CapKey { token_type: utils::type_name_bytes<T>() }
}

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
    xmn_treasury.burn(cap, deny_list, coin_in, ctx);
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
    xmn_treasury.mint(cap, deny_list, amount, receiver, ctx);
}

#[test_only]
public fun execute_transfer_for_testing<T>(
    bridge: &mut Bridge,
    safe: &mut BridgeSafe,
    recipients: vector<address>,
    amounts: vector<u64>,
    batch_nonce_mvx: u64,
    is_batch_complete: bool,
    xmn_treasury: &mut XmnTreasury<T>,
    deny_list: &DenyList,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bridge.pre_execute_transfer_for_testing<T>(batch_nonce_mvx, clock);

    let len = recipients.length();
    let mut i = 0;
    while (i < len) {
        let success = transfer<T>(
            safe,
            bridge.bridge_cap(),
            *recipients.borrow(i),
            *amounts.borrow(i),
            xmn_treasury,
            deny_list,
            ctx,
        );
        bridge.record_transfer_result(batch_nonce_mvx, success);
        i = i + 1;
    };

    bridge.finalize_batch(batch_nonce_mvx, len, is_batch_complete, clock);
}
