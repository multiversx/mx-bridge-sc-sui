#[allow(unused_use)]
module bridge_safe::safe;

use bridge::bridge_env::ctx;
use bridge_safe::events;
use bridge_safe::pausable::{Self, Pause};
use bridge_safe::roles::{AdminCap, BridgeCap, RelayerCap};
use bridge_safe::utils;
use shared_structs::shared_structs::{Self, TokenConfig, Batch, Deposit};
use sui::bag::{Self, Bag};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::table::{Self, Table};

const ENotAdmin: u64 = 0;
const ETokenAlreadyExists: u64 = 2;
const EBatchBlockLimitExceedsSettle: u64 = 5;
const EBatchSettleLimitBelowBlock: u64 = 6;
const EBatchInProgress: u64 = 7;
const EBatchSizeTooLarge: u64 = 8;
const ETokenNotWhitelisted: u64 = 10;
const EAmountBelowMinimum: u64 = 11;
const EAmountAboveMaximum: u64 = 12;
const EInsufficientBalance: u64 = 13;

public struct BridgeSafe has key {
    id: UID,
    pause: Pause,
    admin: address,
    bridge_addr: address,
    batch_size: u16,
    batch_block_limit: u8,
    batch_settle_limit: u8,
    batches_count: u64,
    deposits_count: u64,
    token_cfg: Table<vector<u8>, TokenConfig>,
    batches: Table<u64, Batch>,
    batch_deposits: Table<u64, vector<Deposit>>,
    coin_storage: Bag,
}

fun init(ctx: &mut TxContext) {
    let deployer = tx_context::sender(ctx);
    let (admin_cap, bridge_cap, rel_cap) = bridge_safe::roles::publish_caps(ctx);

    let safe = BridgeSafe {
        id: object::new(ctx),
        pause: pausable::new(),
        admin: deployer,
        bridge_addr: deployer,
        batch_size: 10,
        batch_block_limit: 40,
        batch_settle_limit: 40,
        batches_count: 0,
        deposits_count: 0,
        token_cfg: table::new(ctx),
        batches: table::new(ctx),
        batch_deposits: table::new(ctx),
        coin_storage: bag::new(ctx),
    };

    transfer::public_transfer(admin_cap, deployer);
    transfer::public_transfer(bridge_cap, deployer);
    transfer::public_transfer(rel_cap, deployer);

    transfer::share_object(safe);
}

public entry fun initialize(bridge_addr: address, relayer_addr: address, ctx: &mut TxContext) {
    let (admin_cap, bridge_cap, rel_cap) = bridge_safe::roles::publish_caps(ctx);

    let safe = BridgeSafe {
        id: object::new(ctx),
        pause: pausable::new(),
        admin: tx_context::sender(ctx),
        bridge_addr,
        batch_size: 10,
        batch_block_limit: 40,
        batch_settle_limit: 40,
        batches_count: 0,
        deposits_count: 0,
        token_cfg: table::new(ctx),
        batches: table::new(ctx),
        batch_deposits: table::new(ctx),
        coin_storage: bag::new(ctx),
    };

    transfer::public_transfer(admin_cap, tx_context::sender(ctx));
    transfer::public_transfer(bridge_cap, bridge_addr);
    transfer::public_transfer(rel_cap, relayer_addr);

    transfer::share_object(safe);
}

#[test_only]
public fun publish(
    ctx: &mut TxContext,
    admin_addr: address,
    bridge_addr: address,
): (BridgeSafe, AdminCap, BridgeCap) {
    let (admin_cap, bridge_cap, _rel_cap) = bridge_safe::roles::publish_caps(ctx);
    let safe = BridgeSafe {
        id: object::new(ctx),
        pause: pausable::new(),
        admin: admin_addr,
        bridge_addr,
        batch_size: 10,
        batch_block_limit: 40,
        batch_settle_limit: 40,
        batches_count: 0,
        deposits_count: 0,
        token_cfg: table::new(ctx),
        batches: table::new(ctx),
        batch_deposits: table::new(ctx),
        coin_storage: bag::new(ctx),
    };
    sui::test_utils::destroy(_rel_cap);
    (safe, admin_cap, bridge_cap)
}

fun assert_admin(s: &BridgeSafe, signer: address) {
    assert!(signer == s.admin, ENotAdmin);
}

fun assert_bridge(s: &BridgeSafe, signer: address) {
    assert!(signer == s.bridge_addr, ENotAdmin);
}

fun borrow_token_cfg_mut(safe: &mut BridgeSafe, key: vector<u8>): &mut TokenConfig {
    table::borrow_mut(&mut safe.token_cfg, key)
}

public entry fun whitelist_token<T>(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    minimum_amount: u64,
    maximum_amount: u64,
    is_native: bool,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);

    let key = utils::type_name_bytes<T>();
    let exists = table::contains(&safe.token_cfg, key);
    assert!(!exists, ETokenAlreadyExists);

    let cfg = shared_structs::create_token_config(
        true,
        is_native,
        minimum_amount,
        maximum_amount,
    );
    table::add(&mut safe.token_cfg, key, cfg);
}

public entry fun remove_token_from_whitelist<T>(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    shared_structs::set_token_config_whitelisted(cfg, false);
}

public fun is_token_whitelisted<T>(safe: &BridgeSafe): bool {
    let key = utils::type_name_bytes<T>();
    if (!table::contains(&safe.token_cfg, key)) {
        return false
    };
    let cfg = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_whitelisted(cfg)
}

public entry fun set_batch_block_limit(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    new_limit: u8,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    assert!(new_limit <= safe.batch_settle_limit, EBatchBlockLimitExceedsSettle);
    safe.batch_block_limit = new_limit;
}

public entry fun set_batch_settle_limit(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    new_limit: u8,
    ctx: &mut TxContext,
) {
    pausable::assert_paused(&safe.pause);
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    assert!(new_limit >= safe.batch_block_limit, EBatchSettleLimitBelowBlock);
    assert!(!is_any_batch_in_progress_internal(safe), EBatchInProgress);
    safe.batch_settle_limit = new_limit;
}

public entry fun set_batch_size(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    new_size: u16,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    assert!(new_size <= 100, EBatchSizeTooLarge);
    safe.batch_size = new_size;
}

public entry fun set_token_min_limit<T>(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    shared_structs::set_token_config_min_limit(cfg, amount);
}

public fun get_token_min_limit<T>(safe: &BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    let cfg = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_min_limit(cfg)
}

public entry fun set_token_max_limit<T>(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    shared_structs::set_token_config_max_limit(cfg, amount);
}

public fun get_token_max_limit<T>(safe: &BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    let cfg = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_max_limit(cfg)
}

public entry fun set_admin(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    new_admin: address,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    let previous_admin = safe.admin;
    safe.admin = new_admin;
    events::emit_admin_role_transferred(previous_admin, new_admin);
}

public entry fun set_bridge_addr(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    new_bridge_addr: address,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    let previous_bridge = safe.bridge_addr;
    safe.bridge_addr = new_bridge_addr;
    events::emit_bridge_transferred(previous_bridge, new_bridge_addr);
}

public entry fun init_supply<T>(safe: &mut BridgeSafe, coin_in: Coin<T>, ctx: &mut TxContext) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);

    let key = utils::type_name_bytes<T>();

    assert!(table::contains(&safe.token_cfg, key), ETokenNotWhitelisted);
    let cfg_ref = table::borrow(&safe.token_cfg, key);
    assert!(shared_structs::token_config_whitelisted(cfg_ref), ETokenNotWhitelisted);

    assert!(shared_structs::token_config_is_native(cfg_ref), EInsufficientBalance);

    let amount = coin::value(&coin_in);

    let cfg_mut = borrow_token_cfg_mut(safe, key);
    shared_structs::add_to_token_config_total_balance(cfg_mut, amount);

    if (bag::contains(&safe.coin_storage, key)) {
        let existing_coin = bag::borrow_mut<vector<u8>, Coin<T>>(&mut safe.coin_storage, key);
        coin::join(existing_coin, coin_in);
    } else {
        bag::add(&mut safe.coin_storage, key, coin_in);
    };
}

/// Deposit function: Users send coins FROM their wallet TO the bridge safe contract
/// The coins are stored in the contract's coin_storage for later transfer
public entry fun deposit<T>(
    safe: &mut BridgeSafe,
    coin_in: Coin<T>,
    recipient: address,
    ctx: &mut TxContext,
) {
    pausable::assert_not_paused(&safe.pause);
    let key = utils::type_name_bytes<T>();
    let cfg_ref = table::borrow(&safe.token_cfg, key);
    assert!(shared_structs::token_config_whitelisted(cfg_ref), ETokenNotWhitelisted);

    let amount = coin::value(&coin_in);
    assert!(amount >= shared_structs::token_config_min_limit(cfg_ref), EAmountBelowMinimum);
    assert!(amount <= shared_structs::token_config_max_limit(cfg_ref), EAmountAboveMaximum);

    if (should_create_new_batch_internal(safe)) {
        create_new_batch_internal(safe, ctx);
    };
    let batch_index = safe.batches_count - 1;
    let batch = table::borrow_mut(&mut safe.batches, batch_index);

    let dep_nonce = safe.deposits_count + 1;
    let dep = shared_structs::create_deposit(
        dep_nonce,
        key,
        amount,
        tx_context::sender(ctx),
        recipient,
    );
    if (!table::contains(&safe.batch_deposits, batch_index)) {
        table::add(&mut safe.batch_deposits, batch_index, vector::empty());
    };
    let vec_ref = table::borrow_mut(&mut safe.batch_deposits, batch_index);
    vector::push_back(vec_ref, dep);

    safe.deposits_count = dep_nonce;
    shared_structs::increment_batch_deposits(batch);
    shared_structs::set_batch_last_updated_block(batch, tx_context::epoch(ctx));

    let batch_nonce = shared_structs::batch_nonce(batch);

    let cfg = borrow_token_cfg_mut(safe, key);
    shared_structs::add_to_token_config_total_balance(cfg, amount);

    if (bag::contains(&safe.coin_storage, key)) {
        let existing_coin = bag::borrow_mut<vector<u8>, Coin<T>>(&mut safe.coin_storage, key);
        coin::join(existing_coin, coin_in);
    } else {
        bag::add(&mut safe.coin_storage, key, coin_in);
    };

    events::emit_deposit(
        batch_nonce,
        dep_nonce,
        tx_context::sender(ctx),
        recipient,
        amount,
        key,
    );
}

public fun get_batch(safe: &BridgeSafe, batch_nonce: u64): (Batch, bool) {
    let batch = *table::borrow(&safe.batches, batch_nonce - 1);
    let is_final = is_batch_final_internal(safe, &batch);
    (batch, is_final)
}

public fun get_deposits(safe: &BridgeSafe, batch_nonce: u64): (vector<Deposit>, bool) {
    let batch_index = batch_nonce - 1;
    let deposits = if (table::contains(&safe.batch_deposits, batch_index)) {
        *table::borrow(&safe.batch_deposits, batch_index)
    } else {
        vector::empty()
    };
    let batch = table::borrow(&safe.batches, batch_index);
    let is_final = is_batch_final_internal(safe, batch);
    (deposits, is_final)
}

public fun is_any_batch_in_progress(safe: &BridgeSafe): bool {
    is_any_batch_in_progress_internal(safe)
}

public fun create_new_batch_internal(safe: &mut BridgeSafe, ctx: &mut TxContext) {
    let nonce = safe.batches_count + 1;
    let batch = shared_structs::create_batch(nonce, tx_context::epoch(ctx));
    table::add(&mut safe.batches, safe.batches_count, batch);
    safe.batches_count = nonce;
}

fun should_create_new_batch_internal(safe: &BridgeSafe): bool {
    if (safe.batches_count == 0) { return true };
    let last_index = safe.batches_count - 1;
    let batch = table::borrow(&safe.batches, last_index);
    is_batch_progress_over_internal(safe, shared_structs::batch_deposits_count(batch), shared_structs::batch_block_number(batch)) || (shared_structs::batch_deposits_count(batch) >= safe.batch_size)
}

fun is_batch_progress_over_internal(safe: &BridgeSafe, dep_count: u16, blk: u64): bool {
    if (dep_count == 0) { return false };
    (blk + (safe.batch_block_limit as u64)) < 1000000
}

fun is_batch_final_internal(safe: &BridgeSafe, batch: &Batch): bool {
    (shared_structs::batch_last_updated_block(batch) + (safe.batch_settle_limit as u64)) < 1000000
}

fun is_any_batch_in_progress_internal(safe: &BridgeSafe): bool {
    if (safe.batches_count == 0) { return false };
    let last_index = safe.batches_count - 1;
    if (!should_create_new_batch_internal(safe)) { return true };
    let batch = table::borrow(&safe.batches, last_index);
    !is_batch_final_internal(safe, batch)
}

public fun get_admin(safe: &BridgeSafe): address {
    safe.admin
}

public fun get_bridge_addr(safe: &BridgeSafe): address {
    safe.bridge_addr
}

public fun get_batch_size(safe: &BridgeSafe): u16 {
    safe.batch_size
}

public fun get_batch_block_limit(safe: &BridgeSafe): u8 {
    safe.batch_block_limit
}

public fun get_batch_settle_limit(safe: &BridgeSafe): u8 {
    safe.batch_settle_limit
}

public fun get_batches_count(safe: &BridgeSafe): u64 {
    safe.batches_count
}

public fun get_deposits_count(safe: &BridgeSafe): u64 {
    safe.deposits_count
}

public fun get_pause(safe: &BridgeSafe): &Pause {
    &safe.pause
}

public fun get_pause_mut(safe: &mut BridgeSafe): &mut Pause {
    &mut safe.pause
}

public fun get_batch_nonce(batch: &Batch): u64 {
    shared_structs::batch_nonce(batch)
}

public fun get_batch_deposits_count(batch: &Batch): u16 {
    shared_structs::batch_deposits_count(batch)
}

/// Transfer function: Bridge sends coins FROM the bridge safe contract TO recipient
/// Only the bridge (with BridgeCap) can call this function
/// The coins are taken from the contract's storage and sent to recipient
public fun transfer<T>(
    safe: &mut BridgeSafe,
    _bridge_cap: &BridgeCap,
    receiver: address,
    amount: u64,
    ctx: &mut TxContext,
): bool {
    let key = utils::type_name_bytes<T>();
    assert_bridge(safe, tx_context::sender(ctx));

    if (!table::contains(&safe.token_cfg, key)) {
        return false
    };

    let cfg_ref = table::borrow(&safe.token_cfg, key);
    if (!shared_structs::token_config_whitelisted(cfg_ref)) {
        return false
    };

    let current_balance = shared_structs::token_config_total_balance(cfg_ref);
    if (current_balance < amount) {
        return false
    };

    if (!bag::contains(&safe.coin_storage, key)) {
        return false
    };

    let stored_coin = bag::borrow_mut<vector<u8>, Coin<T>>(&mut safe.coin_storage, key);
    let coin_value = coin::value(stored_coin);
    if (coin_value < amount) {
        return false
    };

    let coin_to_transfer = coin::split(stored_coin, amount, ctx);

    if (coin::value(stored_coin) == 0) {
        let empty_coin = bag::remove<vector<u8>, Coin<T>>(&mut safe.coin_storage, key);
        coin::destroy_zero(empty_coin);
    };

    transfer::public_transfer(coin_to_transfer, receiver);

    let cfg_mut = borrow_token_cfg_mut(safe, key);
    shared_structs::subtract_from_token_config_total_balance(cfg_mut, amount);

    true
}

public fun get_stored_coin_balance<T>(safe: &BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    if (bag::contains(&safe.coin_storage, key)) {
        let stored_coin = bag::borrow<vector<u8>, Coin<T>>(&safe.coin_storage, key);
        coin::value(stored_coin)
    } else {
        0
    }
}

public entry fun pause_contract(safe: &mut BridgeSafe, _admin_cap: &AdminCap, ctx: &mut TxContext) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    pausable::pause(&mut safe.pause);
}

public entry fun unpause_contract(
    safe: &mut BridgeSafe,
    _admin_cap: &AdminCap,
    ctx: &mut TxContext,
) {
    let signer = tx_context::sender(ctx);
    assert_admin(safe, signer);
    pausable::unpause(&mut safe.pause);
}
