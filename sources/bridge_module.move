module bridge_safe::bridge;

use bridge_safe::bridge_roles::BridgeCap;
use bridge_safe::events;
use bridge_safe::pausable::{Self, Pause};
use bridge_safe::safe::{Self, BridgeSafe};
use bridge_safe::utils;
use bridge_safe::version_control;
use locked_token::bridge_token::BRIDGE_TOKEN;
use locked_token::treasury;
use shared_structs::shared_structs::{Self, Deposit, Batch, CrossTransferStatus, DepositStatus};
use std::u64::{min, max};
use sui::address;
use sui::bcs;
use sui::clock::{Self, Clock};
use sui::ed25519;
use sui::event;
use sui::hash::blake2b256;
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

const EQuorumTooLow: u64 = 0;
const EInvalidPublicKeyLength: u64 = 1;
const EInvalidAmountsLength: u64 = 2;
const EBatchAlreadyExecuted: u64 = 3;
const ESettleTimeoutBelowSafeBatch: u64 = 4;
const ENotRelayer: u64 = 5;
const EDepositAlreadyExecuted: u64 = 6;
const EPendingBatches: u64 = 7;
const EInvalidSignature: u64 = 8;
const EDuplicateSignature: u64 = 9;
const EInvalidSignatureLength: u64 = 10;
const EQuorumNotReached: u64 = 11;
const EQuorumExceedsRelayers: u64 = 12;
const ECannotRemoveRelayerBelowQuorum: u64 = 13;
const ERelayerNotFound: u64 = 14;
const ERelayerAlreadyExists: u64 = 15;
const EInvalidDepositNoncesLength: u64 = 16;
const EMigrationStarted: u64 = 17;
const EMigrationNotStarted: u64 = 18;
const ENotPendingVersion: u64 = 19;
const EObjectMigrated: u64 = 20;

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

// === Migration Events ===

public struct BridgeMigrationStarted has copy, drop {
    compatible_versions: vector<u64>,
}

public struct BridgeMigrationAborted has copy, drop {
    compatible_versions: vector<u64>,
}

public struct BridgeMigrationCompleted has copy, drop {
    compatible_versions: vector<u64>,
}

public struct Bridge has key {
    id: UID,
    pause: Pause,
    quorum: u64,
    batch_settle_timeout_ms: u64, // Settlement timeout in milliseconds
    relayers: VecSet<address>,
    relayer_public_keys: Table<address, vector<u8>>, // Maps relayer address to their public key
    executed_batches: VecSet<u64>, // Set of executed batch nonces
    execution_timestamps: Table<u64, u64>, // Maps batch nonce to execution timestamp
    cross_transfer_statuses: Table<u64, CrossTransferStatus>,
    transfer_statuses: vector<DepositStatus>,
    safe: address,
    bridge_cap: BridgeCap,
    executed_transfer_by_batch_type_arg: VecSet<vector<u8>>,
    successful_transfers_by_batch: Table<u64, u64>,
    compatible_versions: VecSet<u64>,
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
        assert!(vector::length(&pk) == ED25519_PUBLIC_KEY_LENGTH, EInvalidPublicKeyLength);
        let relayer_address = getAddressFromPublicKey(&pk);

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
        executed_batches: vec_set::empty<u64>(),
        execution_timestamps: table::new(ctx),
        cross_transfer_statuses: table::new(ctx),
        transfer_statuses: vector::empty<DepositStatus>(),
        safe: safe_address,
        bridge_cap,
        executed_transfer_by_batch_type_arg: vec_set::empty<vector<u8>>(),
        successful_transfers_by_batch: table::new(ctx),
        compatible_versions: vec_set::singleton(version_control::current_version()),
    };

    transfer::share_object(bridge);
}

/// address = blake2b256( 0x00 || ed25519_pubkey )
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
    assert!(!vec_set::contains(&bridge.relayers, &relayer_address), ERelayerAlreadyExists);

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
    vec_set::contains(&bridge.executed_batches, &batch_nonce_mvx)
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
    deposit_nonces: vector<u64>,
    batch_nonce_mvx: u64,
    signatures: vector<vector<u8>>,
    is_batch_complete: bool,
    treasury: &mut treasury::Treasury<BRIDGE_TOKEN>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_relayer(bridge, signer);
    pausable::assert_not_paused(&bridge.pause);
    assert!(!was_batch_executed(bridge, batch_nonce_mvx), EBatchAlreadyExecuted);

    let len = vector::length(&recipients);
    assert!(vector::length(&amounts) == len, EInvalidAmountsLength);
    assert!(vector::length(&deposit_nonces) == len, EInvalidDepositNoncesLength);

    validate_quorum<T>(
        bridge,
        batch_nonce_mvx,
        &recipients,
        &amounts,
        &signatures,
        &deposit_nonces,
    );

    mark_deposits_executed_in_batch_or_abort<T>(bridge, batch_nonce_mvx);

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
            if (table::contains(&bridge.successful_transfers_by_batch, batch_nonce_mvx)) {
                let current_count = table::borrow_mut(
                    &mut bridge.successful_transfers_by_batch,
                    batch_nonce_mvx,
                );
                *current_count = *current_count + 1;
            } else {
                table::add(&mut bridge.successful_transfers_by_batch, batch_nonce_mvx, 1);
            };
        } else {
            vector::push_back(
                &mut bridge.transfer_statuses,
                shared_structs::deposit_status_rejected(),
            );
        };
        i = i + 1;
    };

    if (is_batch_complete) {
        vec_set::insert(&mut bridge.executed_batches, batch_nonce_mvx);

        let cross_status = shared_structs::create_cross_transfer_status(
            bridge.transfer_statuses,
            clock::timestamp_ms(clock),
        );
        table::add(&mut bridge.cross_transfer_statuses, batch_nonce_mvx, cross_status);

        let total_transfers = vector::length(&recipients);
        bridge.transfer_statuses = vector::empty<DepositStatus>();

        let successful_count = if (
            table::contains(&bridge.successful_transfers_by_batch, batch_nonce_mvx)
        ) {
            *table::borrow(&bridge.successful_transfers_by_batch, batch_nonce_mvx)
        } else {
            0
        };

        if (table::contains(&bridge.successful_transfers_by_batch, batch_nonce_mvx)) {
            table::remove(&mut bridge.successful_transfers_by_batch, batch_nonce_mvx);
        };

        event::emit(BatchExecuted {
            batch_nonce_mvx,
            transfers_count: total_transfers,
            successful_transfers: successful_count,
        });
    };
}

fun mark_deposits_executed_in_batch_or_abort<T>(
    bridge: &mut Bridge,
    batch_nonce_mvx: u64,
) {
    let key = derive_key<T>(batch_nonce_mvx);
    assert!(!vec_set::contains(&bridge.executed_transfer_by_batch_type_arg, &key), EDepositAlreadyExecuted);
    vec_set::insert(&mut bridge.executed_transfer_by_batch_type_arg, key);
}

fun derive_key<T>(batch_nonce: u64): vector<u8> {
    let mut data = bcs::to_bytes(&batch_nonce);
    let type_bytes = utils::type_name_bytes<T>();
    vector::append(&mut data, type_bytes);

    blake2b256(&data)
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

public fun get_relayers(bridge: &Bridge): &vector<address> {
    vec_set::keys(&bridge.relayers)
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

fun validate_quorum<T>(
    bridge: &Bridge,
    batch_id: u64,
    recipients: &vector<address>,
    amounts: &vector<u64>,
    signatures: &vector<vector<u8>>,
    deposit_nonces: &vector<u64>,
) {
    let token_bytes = utils::type_name_bytes<T>();
    let num_signatures = vector::length(signatures);
    assert!(num_signatures >= bridge.quorum, EQuorumNotReached);

    let message = compute_message(batch_id, &token_bytes, recipients, amounts, deposit_nonces);

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
    token: &vector<u8>,
    recipients: &vector<address>,
    amounts: &vector<u64>,
    deposit_nonces: &vector<u64>,
): vector<u8> {
    let message = construct_batch_message(batch_id, token, recipients, amounts, deposit_nonces);
    let encoded_msg = bcs::to_bytes(&message);
    let mut intent_message = vector[3u8, 0u8, 0u8];
    vector::append(&mut intent_message, encoded_msg);
    sui::hash::blake2b256(&intent_message)
}

fun construct_batch_message(
    batch_id: u64,
    token: &vector<u8>,
    recipients: &vector<address>,
    amounts: &vector<u64>,
    deposit_nonces: &vector<u64>,
): vector<u8> {
    let mut message = bcs::to_bytes(&batch_id);

    let mut i = 0;
    while (i < vector::length(recipients)) {
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
    batch_nonce_mvx: u64,
    is_batch_complete: bool,
    treasury: &mut treasury::Treasury<BRIDGE_TOKEN>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    mark_deposits_executed_in_batch_or_abort<T>(bridge, batch_nonce_mvx);

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
            if (table::contains(&bridge.successful_transfers_by_batch, batch_nonce_mvx)) {
                let current_count = table::borrow_mut(
                    &mut bridge.successful_transfers_by_batch,
                    batch_nonce_mvx,
                );
                *current_count = *current_count + 1;
            } else {
                table::add(&mut bridge.successful_transfers_by_batch, batch_nonce_mvx, 1);
            };
        } else {
            vector::push_back(
                &mut bridge.transfer_statuses,
                shared_structs::deposit_status_rejected(),
            );

        };
        i = i + 1;
    };

    if (is_batch_complete) {
        vec_set::insert(&mut bridge.executed_batches, batch_nonce_mvx);
        let cross_status = shared_structs::create_cross_transfer_status(
            bridge.transfer_statuses,
            clock::timestamp_ms(clock),
        );
        table::add(&mut bridge.cross_transfer_statuses, batch_nonce_mvx, cross_status);

        let total_transfers = vector::length(&recipients);
        bridge.transfer_statuses = vector::empty<DepositStatus>();

        let successful_count = if (
            table::contains(&bridge.successful_transfers_by_batch, batch_nonce_mvx)
        ) {
            *table::borrow(&bridge.successful_transfers_by_batch, batch_nonce_mvx)
        } else {
            0
        };

        if (table::contains(&bridge.successful_transfers_by_batch, batch_nonce_mvx)) {
            table::remove(&mut bridge.successful_transfers_by_batch, batch_nonce_mvx);
        };

        event::emit(BatchExecuted {
            batch_nonce_mvx,
            transfers_count: total_transfers,
            successful_transfers: successful_count,
        });
    };
}

// === Upgrade Management for Bridge ===

/// Returns the compatible versions for the bridge
public fun bridge_compatible_versions(bridge: &Bridge): vector<u64> {
    *bridge.compatible_versions.keys()
}

/// Returns the current active version (lowest version in the set)
public fun bridge_current_active_version(bridge: &Bridge): u64 {
    let versions = bridge.compatible_versions.keys();
    if (versions.length() == 1) {
        versions[0]
    } else {
        min(versions[0], versions[1])
    }
}

/// Returns the pending version if migration is in progress, otherwise returns none
public fun bridge_pending_version(bridge: &Bridge): Option<u64> {
    if (bridge.compatible_versions.length() == 2) {
        let versions = bridge.compatible_versions.keys();
        option::some(max(versions[0], versions[1]))
    } else {
        option::none()
    }
}

/// Starts the migration process for the bridge
public fun start_bridge_migration(bridge: &mut Bridge, safe: &BridgeSafe, ctx: &TxContext) {
    safe::checkOwnerRole(safe, ctx);
    assert!(bridge.compatible_versions.length() == 1, EMigrationStarted);

    let active_version = bridge.compatible_versions.keys()[0];
    assert!(active_version < version_control::current_version(), EObjectMigrated);

    bridge.compatible_versions.insert(version_control::current_version());

    event::emit(BridgeMigrationStarted {
        compatible_versions: *bridge.compatible_versions.keys(),
    });
}

/// Aborts the migration process for the bridge
public fun abort_bridge_migration(bridge: &mut Bridge, safe: &BridgeSafe, ctx: &TxContext) {
    safe::checkOwnerRole(safe, ctx);
    assert!(bridge.compatible_versions.length() == 2, EMigrationNotStarted);

    let pending_version = max(
        bridge.compatible_versions.keys()[0],
        bridge.compatible_versions.keys()[1],
    );
    assert!(pending_version == version_control::current_version(), ENotPendingVersion);

    bridge.compatible_versions.remove(&pending_version);

    event::emit(BridgeMigrationAborted {
        compatible_versions: *bridge.compatible_versions.keys(),
    });
}

/// Completes the migration process for the bridge
public fun complete_bridge_migration(bridge: &mut Bridge, safe: &BridgeSafe, ctx: &TxContext) {
    safe::checkOwnerRole(safe, ctx);
    assert!(bridge.compatible_versions.length() == 2, EMigrationNotStarted);

    let (version_a, version_b) = (
        bridge.compatible_versions.keys()[0],
        bridge.compatible_versions.keys()[1],
    );
    let (active_version, pending_version) = (min(version_a, version_b), max(version_a, version_b));

    assert!(pending_version == version_control::current_version(), ENotPendingVersion);

    bridge.compatible_versions.remove(&active_version);

    event::emit(BridgeMigrationCompleted {
        compatible_versions: *bridge.compatible_versions.keys(),
    });
}

/// Helper function to check if a bridge migration is in progress
public fun is_bridge_migration_in_progress(bridge: &Bridge): bool {
    bridge.compatible_versions.length() > 1
}

/// [Package private] Asserts that the Bridge object is compatible with current version
public(package) fun assert_bridge_is_compatible(bridge: &Bridge) {
    version_control::assert_object_version_is_compatible_with_package(bridge.compatible_versions);
}

#[test_only]
public fun getAddressFromPublicKeyTest(public_key: &vector<u8>): address {
    getAddressFromPublicKey(public_key)
}

#[test_only]
public fun validate_quorum_for_testing<T>(
    bridge: &Bridge,
    batch_id: u64,
    recipients: &vector<address>,
    amounts: &vector<u64>,
    signatures: &vector<vector<u8>>,
    deposit_nonces: &vector<u64>,
) {
    validate_quorum<T>(bridge, batch_id, recipients, amounts, signatures, deposit_nonces)
}
