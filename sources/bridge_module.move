module bridge_safe::bridge;

use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::events;
use bridge_safe::pausable::{Self, Pause};
use bridge_safe::safe::{Self, BridgeSafe};
use locked_token::bridge_token::BRIDGE_TOKEN;
use locked_token::treasury;
use shared_structs::shared_structs::{Self, Deposit, Batch, CrossTransferStatus, DepositStatus};
use sui::address;
use sui::bcs;
use sui::clock::{Self, Clock};
use sui::ed25519;
use sui::event;
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

const EQuorumTooLow: u64 = 0;
const EBatchAlreadyExecuted: u64 = 3;
const ENotRelayer: u64 = 5;
const EPendingBatches: u64 = 7;
const EInvalidSignature: u64 = 8;
const EDuplicateSignature: u64 = 9;
const EInvalidSignatureLength: u64 = 10;
const EQuorumNotReached: u64 = 11;
const EQuorumExceedsRelayers: u64 = 12;
const ECannotRemoveRelayerBelowQuorum: u64 = 13;
const ERelayerNotFound: u64 = 14;
const EInvalidPublicKeyLength: u64 = 15;
const EDepositAlreadyExecuted: u64 = 16;
const ESettleTimeoutBelowSafeBatch: u64 = 17;
const EInvalidParameterLength: u64 = 18;

const MINIMUM_QUORUM: u64 = 3;
const ED25519_PUBLIC_KEY_LENGTH: u64 = 32;
const SIGNATURE_LENGTH: u64 = 96;
const DEFAULT_BATCH_SETTLE_TIMEOUT_MS: u64 = 10 * 1000;

public struct QuorumChanged has copy, drop {
    new_quorum: u64,
}

public struct BatchExecuted has copy, drop {
    batch_nonce_mvx: u64,
    transfers_count: u64,
    successful_transfers: u64,
}

public struct Bridge has key {
    id: UID,
    pause: Pause,
    quorum: u64,
    batch_settle_timeout_ms: u64, // Settlement timeout in milliseconds
    relayers: VecSet<address>,
    relayer_public_keys: Table<address, vector<u8>>, // Maps relayer address to their public key
    executed_batches: Table<u64, bool>,
    execution_timestamps: Table<u64, u64>, // Maps batch nonce to execution timestamp
    cross_transfer_statuses: Table<u64, CrossTransferStatus>,
    transfer_statuses: vector<DepositStatus>,
    safe: address,
    bridge_cap: BridgeCap,
    executed_deposits_by_batch: Table<u64, VecSet<u64>>, // Maps batch_nonce -> set(deposit_nonce)
    successful_deposits_by_batch: Table<u64, u64>, // Maps batch_nonce -> count(deposit_nonce)
    failed_deposits_by_batch: Table<u64, u64>, // Maps batch_nonce -> count(deposit_nonce)
}

public fun initialize(
    public_keys: vector<vector<u8>>,
    initial_quorum: u64,
    safe_address: address,
    bridge_cap: BridgeCap,
    ctx: &mut TxContext,
) {
    assert!(initial_quorum >= MINIMUM_QUORUM, EQuorumTooLow);

    let mut relayers = vec_set::empty<address>();
    let mut relayer_public_keys = table::new<address, vector<u8>>(ctx);
    let mut i = 0;
    while (i < vector::length(&public_keys)) {
        let pk = *vector::borrow(&public_keys, i);
        let relayer_address = getAddressFromPublicKey(&pk);
        assert!(vector::length(&pk) == ED25519_PUBLIC_KEY_LENGTH, EInvalidPublicKeyLength);

        vec_set::insert(&mut relayers, relayer_address);
        table::add(&mut relayer_public_keys, relayer_address, pk);
        i = i + 1;
    };

    let bridge = Bridge {
        id: object::new(ctx),
        pause: pausable::new(),
        quorum: initial_quorum,
        batch_settle_timeout_ms: DEFAULT_BATCH_SETTLE_TIMEOUT_MS,
        relayers,
        relayer_public_keys,
        executed_batches: table::new(ctx),
        execution_timestamps: table::new(ctx),
        cross_transfer_statuses: table::new(ctx),
        transfer_statuses: vector::empty<DepositStatus>(),
        safe: safe_address,
        bridge_cap,
        executed_deposits_by_batch: table::new(ctx),
        successful_deposits_by_batch: table::new(ctx),
        failed_deposits_by_batch: table::new(ctx),
    };

    transfer::share_object(bridge);
}

fun getAddressFromPublicKey(public_key: &vector<u8>): address {
    let mut long_public_key = vector[0u8]; 
    vector::append(&mut long_public_key, *public_key); 
    let relayer_bytes = sui::hash::blake2b256(&long_public_key);
    address::from_bytes(relayer_bytes)
}

fun assert_relayer(bridge: &Bridge, signer: address) {
    assert!(vec_set::contains(&bridge.relayers, &signer), ENotRelayer);
}

public fun set_quorum(
    bridge: &mut Bridge,
    safe: &BridgeSafe,
    new_quorum: u64,
    ctx: &mut TxContext,
) {
    safe::checkOwnerRole(safe, ctx);

    assert!(new_quorum >= MINIMUM_QUORUM, EQuorumTooLow);
    assert!(new_quorum <= vec_set::length(&bridge.relayers), EQuorumExceedsRelayers);

    bridge.quorum = new_quorum;
    event::emit(QuorumChanged { new_quorum });
}

public fun set_batch_settle_timeout_ms(
    bridge: &mut Bridge,
    safe: &BridgeSafe,
    new_timeout_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    safe::checkOwnerRole(safe, ctx);

    pausable::assert_paused(&bridge.pause);
    assert!(new_timeout_ms >= safe::get_batch_timeout_ms(safe), ESettleTimeoutBelowSafeBatch);
    assert!(!safe::is_any_batch_in_progress(safe, clock), EPendingBatches);

    bridge.batch_settle_timeout_ms = new_timeout_ms;
}

public fun add_relayer(
    bridge: &mut Bridge,
    safe: &BridgeSafe,
    public_key: vector<u8>,
    ctx: &mut TxContext,
) {
    safe::checkOwnerRole(safe, ctx);

    assert!(vector::length(&public_key) == ED25519_PUBLIC_KEY_LENGTH, EInvalidPublicKeyLength);
    let relayer_address = getAddressFromPublicKey(&public_key);

    vec_set::insert(&mut bridge.relayers, relayer_address);
    table::add(&mut bridge.relayer_public_keys, relayer_address, public_key);
    events::emit_relayer_added(relayer_address, tx_context::sender(ctx));
}

public fun remove_relayer(
    bridge: &mut Bridge,
    safe: &BridgeSafe,
    relayer: address,
    ctx: &mut TxContext,
) {
    safe::checkOwnerRole(safe, ctx);

    let current_count = vec_set::length(&bridge.relayers);
    assert!(current_count > bridge.quorum, ECannotRemoveRelayerBelowQuorum);

    vec_set::remove(&mut bridge.relayers, &relayer);
    if (table::contains(&bridge.relayer_public_keys, relayer)) {
        table::remove(&mut bridge.relayer_public_keys, relayer);
    };
    events::emit_relayer_removed(relayer, tx_context::sender(ctx));
}

public fun get_batch(safe: &BridgeSafe, batch_nonce: u64, clock: &Clock): (Batch, bool) {
    safe::get_batch(safe, batch_nonce, clock)
}

public fun get_batch_deposits(
    safe: &BridgeSafe,
    batch_nonce: u64,
    clock: &Clock,
): (vector<Deposit>, bool) {
    safe::get_deposits(safe, batch_nonce, clock)
}

public fun was_batch_executed(bridge: &Bridge, batch_nonce_mvx: u64): bool {
    if (table::contains(&bridge.executed_batches, batch_nonce_mvx)) {
        *table::borrow(&bridge.executed_batches, batch_nonce_mvx)
    } else {
        false
    }
}

public fun get_statuses_after_execution(
    bridge: &Bridge,
    batch_nonce_mvx: u64,
    clock: &Clock,
): (vector<DepositStatus>, bool) {
    if (table::contains(&bridge.cross_transfer_statuses, batch_nonce_mvx)) {
        let cross_status = table::borrow(&bridge.cross_transfer_statuses, batch_nonce_mvx);
        let statuses = shared_structs::cross_transfer_status_statuses(cross_status);
        let created_timestamp = shared_structs::cross_transfer_status_created_timestamp_ms(
            cross_status,
        );
        let is_final = is_mvx_batch_final(bridge, created_timestamp, clock);
        (statuses, is_final)
    } else {
        (vector::empty<DepositStatus>(), false)
    }
}

public fun execute_transfer<T>(
    bridge: &mut Bridge,
    safe: &mut BridgeSafe,
    recipients: vector<address>,
    amounts: vector<u64>,
    tokens: vector<vector<u8>>,
    deposit_nonces: vector<u64>,
    batch_nonce_mvx: u64,
    signatures: vector<vector<u8>>,
    is_batch_complete: bool,
    treasury: &mut treasury::Treasury<BRIDGE_TOKEN>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Validate parameter vectors have equal lengths
    let len = vector::length(&tokens);
    assert!(vector::length(&recipients) == len, EInvalidParameterLength);
    assert!(vector::length(&amounts) == len, EInvalidParameterLength);
    assert!(vector::length(&deposit_nonces) == len, EInvalidParameterLength);

    let signer = tx_context::sender(ctx);
    assert_relayer(bridge, signer);
    pausable::assert_not_paused(&bridge.pause);

    assert!(!was_batch_executed(bridge, batch_nonce_mvx), EBatchAlreadyExecuted);

    validate_quorum(
        bridge,
        batch_nonce_mvx,
        &tokens,
        &recipients,
        &amounts,
        &signatures,
        &deposit_nonces,
    );

    mark_deposits_executed_in_batch_or_abort(bridge, batch_nonce_mvx, &deposit_nonces);

    if (table::contains(&bridge.executed_batches, batch_nonce_mvx)) {
        let v = table::borrow_mut(&mut bridge.executed_batches, batch_nonce_mvx);
        *v = is_batch_complete;
    } else {
        table::add(&mut bridge.executed_batches, batch_nonce_mvx, is_batch_complete);
    };
    let now = clock::timestamp_ms(clock);
    if (table::contains(&bridge.execution_timestamps, batch_nonce_mvx)) {
        let t = table::borrow_mut(&mut bridge.execution_timestamps, batch_nonce_mvx);
        *t = now;
    } else {
        table::add(&mut bridge.execution_timestamps, batch_nonce_mvx, now);
    };

    let mut i = 0;
    while (i < vector::length(&recipients)) {
        let recipient = *vector::borrow(&recipients, i);
        let amount = *vector::borrow(&amounts, i);

        let success = safe::transfer<T>(safe, &bridge.bridge_cap, recipient, amount, treasury, ctx);
        if (success) {
            vector::push_back(
                &mut bridge.transfer_statuses,
                shared_structs::deposit_status_executed(),
            );

            // Increment successful deposits count
            if (table::contains(&bridge.successful_deposits_by_batch, batch_nonce_mvx)) {
                let current_count = table::borrow_mut(
                    &mut bridge.successful_deposits_by_batch,
                    batch_nonce_mvx,
                );
                *current_count = *current_count + 1;
            } else {
                table::add(&mut bridge.successful_deposits_by_batch, batch_nonce_mvx, 1);
            };
        } else {
            vector::push_back(
                &mut bridge.transfer_statuses,
                shared_structs::deposit_status_rejected(),
            );

            // Increment failed deposits count
            if (table::contains(&bridge.failed_deposits_by_batch, batch_nonce_mvx)) {
                let current_count = table::borrow_mut(
                    &mut bridge.failed_deposits_by_batch,
                    batch_nonce_mvx,
                );
                *current_count = *current_count + 1;
            } else {
                table::add(&mut bridge.failed_deposits_by_batch, batch_nonce_mvx, 1);
            };
        };
        i = i + 1;
    };

    if (is_batch_complete) {
        let cross_status = shared_structs::create_cross_transfer_status(
            bridge.transfer_statuses,
            clock::timestamp_ms(clock),
        );
        table::add(&mut bridge.cross_transfer_statuses, batch_nonce_mvx, cross_status);

        let total_transfers = vector::length(&recipients);
        bridge.transfer_statuses = vector::empty<DepositStatus>();

        let successful_count = if (
            table::contains(&bridge.successful_deposits_by_batch, batch_nonce_mvx)
        ) {
            *table::borrow(&bridge.successful_deposits_by_batch, batch_nonce_mvx)
        } else {
            0
        };

        // Clean up all tracking tables since batch is complete
        if (table::contains(&bridge.executed_deposits_by_batch, batch_nonce_mvx)) {
            table::remove(&mut bridge.executed_deposits_by_batch, batch_nonce_mvx);
        };
        if (table::contains(&bridge.successful_deposits_by_batch, batch_nonce_mvx)) {
            table::remove(&mut bridge.successful_deposits_by_batch, batch_nonce_mvx);
        };
        if (table::contains(&bridge.failed_deposits_by_batch, batch_nonce_mvx)) {
            table::remove(&mut bridge.failed_deposits_by_batch, batch_nonce_mvx);
        };

        event::emit(BatchExecuted {
            batch_nonce_mvx,
            transfers_count: total_transfers,
            successful_transfers: successful_count,
        });
    };
}

fun mark_deposits_executed_in_batch_or_abort(
    bridge: &mut Bridge,
    batch_nonce_mvx: u64,
    deposit_nonces: &vector<u64>,
) {
    if (!table::contains(&bridge.executed_deposits_by_batch, batch_nonce_mvx)) {
        let set = vec_set::empty<u64>();
        table::add(&mut bridge.executed_deposits_by_batch, batch_nonce_mvx, set);
    };

    let set_ref = table::borrow_mut(&mut bridge.executed_deposits_by_batch, batch_nonce_mvx);

    let mut i = 0;
    while (i < vector::length(deposit_nonces)) {
        let dn = *vector::borrow(deposit_nonces, i);
        assert!(!vec_set::contains(set_ref, &dn), EDepositAlreadyExecuted);
        i = i + 1;
    };

    let mut j = 0;
    while (j < vector::length(deposit_nonces)) {
        let dn = *vector::borrow(deposit_nonces, j);
        vec_set::insert(set_ref, dn);
        j = j + 1;
    };
}

fun is_mvx_batch_final(bridge: &Bridge, created_timestamp_ms: u64, clock: &Clock): bool {
    if (created_timestamp_ms == 0) {
        false
    } else {
        (created_timestamp_ms + bridge.batch_settle_timeout_ms) <= clock::timestamp_ms(clock)
    }
}

public fun get_quorum(bridge: &Bridge): u64 {
    bridge.quorum
}

public fun get_batch_settle_timeout_ms(bridge: &Bridge): u64 {
    bridge.batch_settle_timeout_ms
}

public fun is_relayer(bridge: &Bridge, addr: address): bool {
    vec_set::contains(&bridge.relayers, &addr)
}

public fun get_admin(safe: &BridgeSafe): address {
    safe::get_owner(safe)
}

public fun get_pause(bridge: &Bridge): bool {
    bridge.pause.is_paused()
}

public fun get_relayers(bridge: &Bridge): vector<address> {
    *vec_set::keys(&bridge.relayers)
}

public fun get_relayer_count(bridge: &Bridge): u64 {
    vec_set::length(&bridge.relayers)
}

public fun pause_contract(bridge: &mut Bridge, safe: &BridgeSafe, ctx: &mut TxContext) {
    safe::checkOwnerRole(safe, ctx);
    pausable::pause(&mut bridge.pause);
}

public fun unpause_contract(bridge: &mut Bridge, safe: &BridgeSafe, ctx: &mut TxContext) {
    safe::checkOwnerRole(safe, ctx);
    pausable::unpause(&mut bridge.pause);
}

fun validate_quorum(
    bridge: &Bridge,
    batch_id: u64,
    tokens: &vector<vector<u8>>,
    recipients: &vector<address>,
    amounts: &vector<u64>,
    signatures: &vector<vector<u8>>,
    deposit_nonces: &vector<u64>,
) {
    let num_signatures = vector::length(signatures);
    assert!(num_signatures >= bridge.quorum, EQuorumNotReached);

    let message = compute_message(batch_id, tokens, recipients, amounts, deposit_nonces);

    let mut verified_relayers = vec_set::empty<address>();
    let mut i = 0;

    while (i < num_signatures) {
        let signature = vector::borrow(signatures, i);

        assert!(vector::length(signature) == SIGNATURE_LENGTH, EInvalidSignatureLength);

        let public_key = extract_public_key(signature);
        let sig_bytes = extract_signature(signature);

        let mut relayer_opt = find_relayer_by_public_key(bridge, &public_key);
        assert!(option::is_some(&relayer_opt), ERelayerNotFound);

        let relayer = option::extract(&mut relayer_opt);

        assert!(!vec_set::contains(&verified_relayers, &relayer), EDuplicateSignature);

        assert!(ed25519::ed25519_verify(&sig_bytes, &public_key, &message), EInvalidSignature);

        vec_set::insert(&mut verified_relayers, relayer);
        i = i + 1;
    };

    assert!(vec_set::length(&verified_relayers) >= bridge.quorum, EQuorumNotReached);
}

public fun compute_message(
    batch_id: u64,
    tokens: &vector<vector<u8>>,
    recipients: &vector<address>,
    amounts: &vector<u64>,
    deposit_nonces: &vector<u64>,
): vector<u8> {
    let message = construct_batch_message(batch_id, tokens, recipients, amounts, deposit_nonces);
    let encoded_msg = bcs::to_bytes(&message);
    let mut intent_message = vector[3u8, 0u8, 0u8];
    vector::append(&mut intent_message, encoded_msg);
    sui::hash::blake2b256(&intent_message)
}

fun construct_batch_message(
    batch_id: u64,
    tokens: &vector<vector<u8>>,
    recipients: &vector<address>,
    amounts: &vector<u64>,
    deposit_nonces: &vector<u64>,
): vector<u8> {
    let mut message = bcs::to_bytes(&batch_id);

    let mut i = 0;
    while (i < vector::length(tokens)) {
        let token = vector::borrow(tokens, i);
        let recipient = vector::borrow(recipients, i);
        let amount = vector::borrow(amounts, i);
        let deposit_nonce = vector::borrow(deposit_nonces, i);

        vector::append(&mut message, bcs::to_bytes(token));
        vector::append(&mut message, bcs::to_bytes(recipient));
        vector::append(&mut message, bcs::to_bytes(amount));
        vector::append(&mut message, bcs::to_bytes(deposit_nonce));
        i = i + 1;
    };

    sui::hash::blake2b256(&message)
}

fun extract_public_key(signature: &vector<u8>): vector<u8> {
    let mut public_key = vector::empty<u8>();
    let mut i = vector::length(signature) - ED25519_PUBLIC_KEY_LENGTH;
    while (i < vector::length(signature)) {
        vector::push_back(&mut public_key, *vector::borrow(signature, i));
        i = i + 1;
    };
    public_key
}

fun extract_signature(signature: &vector<u8>): vector<u8> {
    let mut sig_bytes = vector::empty<u8>();
    let mut i = 0;
    while (i < vector::length(signature) - ED25519_PUBLIC_KEY_LENGTH) {
        vector::push_back(&mut sig_bytes, *vector::borrow(signature, i));
        i = i + 1;
    };
    sig_bytes
}

fun find_relayer_by_public_key(bridge: &Bridge, public_key: &vector<u8>): Option<address> {
    let relayers = vec_set::keys(&bridge.relayers);
    let mut i = 0;

    while (i < vector::length(relayers)) {
        let relayer = *vector::borrow(relayers, i);
        if (table::contains(&bridge.relayer_public_keys, relayer)) {
            let stored_pk = table::borrow(&bridge.relayer_public_keys, relayer);
            if (stored_pk == public_key) {
                return option::some(relayer)
            };
        };
        i = i + 1;
    };

    option::none()
}

#[test_only]
public fun execute_transfer_for_testing<T>(
    bridge: &mut Bridge,
    safe: &mut BridgeSafe,
    recipients: vector<address>,
    amounts: vector<u64>,
    deposit_nonces: vector<u64>,
    batch_nonce_mvx: u64,
    is_batch_complete: bool,
    treasury: &mut treasury::Treasury<BRIDGE_TOKEN>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    mark_deposits_executed_in_batch_or_abort(bridge, batch_nonce_mvx, &deposit_nonces);

    if (table::contains(&bridge.executed_batches, batch_nonce_mvx)) {
        let v = table::borrow_mut(&mut bridge.executed_batches, batch_nonce_mvx);
        *v = is_batch_complete;
    } else {
        table::add(&mut bridge.executed_batches, batch_nonce_mvx, is_batch_complete);
    };
    let now = clock::timestamp_ms(clock);
    if (table::contains(&bridge.execution_timestamps, batch_nonce_mvx)) {
        let t = table::borrow_mut(&mut bridge.execution_timestamps, batch_nonce_mvx);
        *t = now;
    } else {
        table::add(&mut bridge.execution_timestamps, batch_nonce_mvx, now);
    };

    let mut i = 0;
    while (i < vector::length(&recipients)) {
        let recipient = *vector::borrow(&recipients, i);
        let amount = *vector::borrow(&amounts, i);

        let success = safe::transfer<T>(safe, &bridge.bridge_cap, recipient, amount, treasury, ctx);
        if (success) {
            vector::push_back(
                &mut bridge.transfer_statuses,
                shared_structs::deposit_status_executed(),
            );

            // Increment successful deposits count
            if (table::contains(&bridge.successful_deposits_by_batch, batch_nonce_mvx)) {
                let current_count = table::borrow_mut(
                    &mut bridge.successful_deposits_by_batch,
                    batch_nonce_mvx,
                );
                *current_count = *current_count + 1;
            } else {
                table::add(&mut bridge.successful_deposits_by_batch, batch_nonce_mvx, 1);
            };
        } else {
            vector::push_back(
                &mut bridge.transfer_statuses,
                shared_structs::deposit_status_rejected(),
            );

            // Increment failed deposits count
            if (table::contains(&bridge.failed_deposits_by_batch, batch_nonce_mvx)) {
                let current_count = table::borrow_mut(
                    &mut bridge.failed_deposits_by_batch,
                    batch_nonce_mvx,
                );
                *current_count = *current_count + 1;
            } else {
                table::add(&mut bridge.failed_deposits_by_batch, batch_nonce_mvx, 1);
            };
        };
        i = i + 1;
    };

    if (is_batch_complete) {
        let cross_status = shared_structs::create_cross_transfer_status(
            bridge.transfer_statuses,
            clock::timestamp_ms(clock),
        );
        table::add(&mut bridge.cross_transfer_statuses, batch_nonce_mvx, cross_status);

        let total_transfers = vector::length(&recipients);
        bridge.transfer_statuses = vector::empty<DepositStatus>();

        let successful_count = if (
            table::contains(&bridge.successful_deposits_by_batch, batch_nonce_mvx)
        ) {
            *table::borrow(&bridge.successful_deposits_by_batch, batch_nonce_mvx)
        } else {
            0
        };

        // Clean up all tracking tables since batch is complete
        if (table::contains(&bridge.executed_deposits_by_batch, batch_nonce_mvx)) {
            table::remove(&mut bridge.executed_deposits_by_batch, batch_nonce_mvx);
        };
        if (table::contains(&bridge.successful_deposits_by_batch, batch_nonce_mvx)) {
            table::remove(&mut bridge.successful_deposits_by_batch, batch_nonce_mvx);
        };
        if (table::contains(&bridge.failed_deposits_by_batch, batch_nonce_mvx)) {
            table::remove(&mut bridge.failed_deposits_by_batch, batch_nonce_mvx);
        };

        event::emit(BatchExecuted {
            batch_nonce_mvx,
            transfers_count: total_transfers,
            successful_transfers: successful_count,
        });
    }
}

#[test_only]
public fun getAddressFromPublicKeyTest(public_key: &vector<u8>): address {
    getAddressFromPublicKey(public_key)
}
