module bridge_safe::bridge;

use bridge_safe::events;
use bridge_safe::pausable::{Self, Pause};
use bridge_safe::roles::{BridgeCap, AdminCap};
use bridge_safe::safe::{Self, BridgeSafe};
use shared_structs::shared_structs::{Self, Deposit, Batch, CrossTransferStatus, DepositStatus};
use sui::event;
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

const EQuorumTooLow: u64 = 0;
const EBoardTooSmall: u64 = 1;
const ENotEnoughSignatures: u64 = 2;
const EBatchAlreadyExecuted: u64 = 3;
const EQuorumNotMet: u64 = 4;
const ENotRelayer: u64 = 5;
const ENotAdmin: u64 = 6;
const EPendingBatches: u64 = 7;

const MINIMUM_QUORUM: u64 = 3;

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
    admin: address,
    quorum: u64,
    batch_settle_block_count: u64,
    relayers: VecSet<address>,
    executed_batches: Table<u64, bool>,
    execution_blocks: Table<u64, u64>,
    cross_transfer_statuses: Table<u64, CrossTransferStatus>,
    safe: address,
}

public entry fun initialize(
    board: vector<address>,
    initial_quorum: u64,
    safe_address: address,
    ctx: &mut TxContext,
) {
    assert!(initial_quorum >= MINIMUM_QUORUM, EQuorumTooLow);
    assert!(vector::length(&board) >= initial_quorum, EBoardTooSmall);

    let mut relayers = vec_set::empty<address>();
    let mut i = 0;
    while (i < vector::length(&board)) {
        vec_set::insert(&mut relayers, *vector::borrow(&board, i));
        i = i + 1;
    };

    let bridge = Bridge {
        id: object::new(ctx),
        pause: pausable::new(),
        admin: tx_context::sender(ctx),
        quorum: initial_quorum,
        batch_settle_block_count: 40,
        relayers,
        executed_batches: table::new(ctx),
        execution_blocks: table::new(ctx),
        cross_transfer_statuses: table::new(ctx),
        safe: safe_address,
    };

    transfer::share_object(bridge);
}

#[test_only]
public fun test_initialize(
    board: vector<address>,
    initial_quorum: u64,
    safe_address: address,
    ctx: &mut TxContext,
): Bridge {
    assert!(initial_quorum >= MINIMUM_QUORUM, EQuorumTooLow);
    assert!(vector::length(&board) >= initial_quorum, EBoardTooSmall);

    let mut relayers = vec_set::empty<address>();
    let mut i = 0;
    while (i < vector::length(&board)) {
        vec_set::insert(&mut relayers, *vector::borrow(&board, i));
        i = i + 1;
    };

    Bridge {
        id: object::new(ctx),
        pause: pausable::new(),
        admin: tx_context::sender(ctx),
        quorum: initial_quorum,
        batch_settle_block_count: 40,
        relayers,
        executed_batches: table::new(ctx),
        execution_blocks: table::new(ctx),
        cross_transfer_statuses: table::new(ctx),
        safe: safe_address,
    }
}

fun assert_admin(bridge: &Bridge, signer: address) {
    assert!(signer == bridge.admin, ENotAdmin);
}

fun assert_relayer(bridge: &Bridge, signer: address) {
    assert!(vec_set::contains(&bridge.relayers, &signer), ENotRelayer);
}

public entry fun set_quorum(
    bridge: &mut Bridge,
    _admin_cap: &AdminCap,
    new_quorum: u64,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(bridge, signer);
    assert!(new_quorum >= MINIMUM_QUORUM, EQuorumTooLow);

    bridge.quorum = new_quorum;
    event::emit(QuorumChanged { new_quorum });
}

public entry fun set_batch_settle_limit(
    bridge: &mut Bridge,
    _admin_cap: &AdminCap,
    safe: &BridgeSafe,
    new_batch_settle_limit: u64,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(bridge, signer);
    pausable::assert_paused(&bridge.pause);
    assert!(!safe::is_any_batch_in_progress(safe), EPendingBatches);

    bridge.batch_settle_block_count = new_batch_settle_limit;
}

public entry fun add_relayer(
    bridge: &mut Bridge,
    _admin_cap: &AdminCap,
    relayer: address,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(bridge, signer);
    vec_set::insert(&mut bridge.relayers, relayer);
    events::emit_relayer_added(relayer, signer);
}

public entry fun remove_relayer(
    bridge: &mut Bridge,
    _admin_cap: &AdminCap,
    relayer: address,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(bridge, signer);
    vec_set::remove(&mut bridge.relayers, &relayer);
    events::emit_relayer_removed(relayer, signer);
}

public fun get_batch(safe: &BridgeSafe, batch_nonce: u64): (Batch, bool) {
    safe::get_batch(safe, batch_nonce)
}

public fun get_batch_deposits(safe: &BridgeSafe, batch_nonce: u64): (vector<Deposit>, bool) {
    safe::get_deposits(safe, batch_nonce)
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
    ctx: &TxContext,
): (vector<DepositStatus>, bool) {
    if (table::contains(&bridge.cross_transfer_statuses, batch_nonce_mvx)) {
        let cross_status = table::borrow(&bridge.cross_transfer_statuses, batch_nonce_mvx);
        let statuses = shared_structs::cross_transfer_status_statuses(cross_status);
        let created_block = shared_structs::cross_transfer_status_created_block_number(
            cross_status,
        );
        let is_final = is_mvx_batch_final(bridge, created_block, ctx);
        (statuses, is_final)
    } else {
        (vector::empty<DepositStatus>(), false)
    }
}

public entry fun execute_transfer<T>(
    bridge: &mut Bridge,
    safe: &mut BridgeSafe,
    _bridge_cap: &BridgeCap,
    tokens: vector<vector<u8>>,
    recipients: vector<address>,
    amounts: vector<u64>,
    batch_nonce_mvx: u64,
    signatures: vector<vector<u8>>,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_relayer(bridge, signer);
    pausable::assert_not_paused(&bridge.pause);

    assert!(vector::length(&signatures) >= bridge.quorum, ENotEnoughSignatures);
    assert!(!was_batch_executed(bridge, batch_nonce_mvx), EBatchAlreadyExecuted);

    table::add(&mut bridge.executed_batches, batch_nonce_mvx, true);
    table::add(&mut bridge.execution_blocks, batch_nonce_mvx, tx_context::epoch(ctx));

    let mut successful_count = 0;
    let mut failed_count = 0;
    let mut transfer_statuses = vector::empty<DepositStatus>();
    let mut i = 0;
    while (i < vector::length(&tokens)) {
        let recipient = *vector::borrow(&recipients, i);
        let amount = *vector::borrow(&amounts, i);

        let success = try_transfer<T>(safe, _bridge_cap, recipient, amount, ctx);
        if (success) {
            successful_count = successful_count + 1;
            vector::push_back(&mut transfer_statuses, shared_structs::deposit_status_executed());
        } else {
            failed_count = failed_count + 1;
            vector::push_back(&mut transfer_statuses, shared_structs::deposit_status_rejected());
        };
        i = i + 1;
    };

    let cross_status = shared_structs::create_cross_transfer_status(
        transfer_statuses,
        tx_context::epoch(ctx),
    );
    table::add(&mut bridge.cross_transfer_statuses, batch_nonce_mvx, cross_status);

    let total_transfers = vector::length(&tokens);

    event::emit(BatchExecuted {
        batch_nonce_mvx,
        transfers_count: total_transfers,
        successful_transfers: successful_count,
    });
}

fun try_transfer<T>(
    safe: &mut BridgeSafe,
    bridge_cap: &BridgeCap,
    recipient: address,
    amount: u64,
    ctx: &mut TxContext,
): bool {
    safe::transfer<T>(safe, bridge_cap, recipient, amount, ctx)
}

fun is_mvx_batch_final(bridge: &Bridge, created_block_number: u64, ctx: &TxContext): bool {
    if (created_block_number == 0) {
        false
    } else {
        (created_block_number + bridge.batch_settle_block_count) <= tx_context::epoch(ctx)
    }
}

public fun get_quorum(bridge: &Bridge): u64 {
    bridge.quorum
}

public fun get_batch_settle_block_count(bridge: &Bridge): u64 {
    bridge.batch_settle_block_count
}

public fun is_relayer(bridge: &Bridge, addr: address): bool {
    vec_set::contains(&bridge.relayers, &addr)
}

public fun get_admin(bridge: &Bridge): address {
    bridge.admin
}

public fun get_pause(bridge: &Bridge): &Pause {
    &bridge.pause
}

public fun get_pause_mut(bridge: &mut Bridge): &mut Pause {
    &mut bridge.pause
}

public fun get_relayers(bridge: &Bridge): &VecSet<address> {
    &bridge.relayers
}

public fun get_relayer_count(bridge: &Bridge): u64 {
    vec_set::size(&bridge.relayers)
}

public entry fun set_admin(
    bridge: &mut Bridge,
    _admin_cap: &AdminCap,
    new_admin: address,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(bridge, signer);
    let previous_admin = bridge.admin;
    bridge.admin = new_admin;
    events::emit_admin_role_transferred(previous_admin, new_admin);
}

public entry fun pause_contract(bridge: &mut Bridge, _admin_cap: &AdminCap, ctx: &mut TxContext) {
    let signer = tx_context::sender(ctx);
    assert_admin(bridge, signer);
    pausable::pause(&mut bridge.pause);
}

public entry fun unpause_contract(bridge: &mut Bridge, _admin_cap: &AdminCap, ctx: &mut TxContext) {
    let signer = tx_context::sender(ctx);
    assert_admin(bridge, signer);
    pausable::unpause(&mut bridge.pause);
}
