module bridge_safe::safe;

use bridge_safe::bridge_roles::{Self, Roles, BridgeSafeTag};
use bridge_safe::events;
use bridge_safe::pausable::{Self, Pause};
use bridge_safe::utils;
use locked_token::bridge_token::BRIDGE_TOKEN;
use locked_token::treasury;
use shared_structs::shared_structs::{Self, TokenConfig, Batch, Deposit};
use sui::bag::{Self, Bag};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::table::{Self, Table};

const ETokenAlreadyExists: u64 = 2;
const EBatchBlockLimitExceedsSettle: u64 = 5;
const EBatchSettleLimitBelowBlock: u64 = 6;
const EBatchInProgress: u64 = 7;
const EBatchSizeTooLarge: u64 = 8;
const ETokenNotWhitelisted: u64 = 10;
const EAmountBelowMinimum: u64 = 11;
const EAmountAboveMaximum: u64 = 12;
const EInsufficientBalance: u64 = 13;
const EInvalidRecipient: u64 = 14;
const EZeroAmount: u64 = 15;
const EOverflow: u64 = 16;
const EBatchNotFound: u64 = 17;
const EBatchSizeZero: u64 = 18;
const EInvalidTokenLimits: u64 = 19;

const MAX_U64: u64 = 18446744073709551615;
const DEFAULT_BATCH_TIMEOUT_MS: u64 = 5 * 1000; // 5 seconds
const DEFAULT_BATCH_SETTLE_TIMEOUT_MS: u64 = 10 * 1000; // 10 seconds

public struct BridgeSafe has key {
    id: UID,
    pause: Pause,
    roles: Roles<BridgeSafeTag>,
    bridge_addr: address,
    batch_size: u16,
    batch_timeout_ms: u64, // Timeout in milliseconds for batch progress
    batch_settle_timeout_ms: u64, // Timeout in milliseconds for batch settlement
    batches_count: u64,
    deposits_count: u64,
    token_cfg: Table<vector<u8>, TokenConfig>,
    batches: Table<u64, Batch>,
    batch_deposits: Table<u64, vector<Deposit>>,
    coin_storage: Bag,
    from_coin_cap: treasury::FromCoinCap<BRIDGE_TOKEN>,
}

#[allow(lint(self_transfer))]
public fun initialize(from_coin_cap: treasury::FromCoinCap<BRIDGE_TOKEN>, ctx: &mut TxContext) {
    let deployer = tx_context::sender(ctx);
    let w = bridge_roles::grant_witness();
    let (bridge_cap) = bridge_roles::publish_caps(w, ctx);

    let safe = BridgeSafe {
        id: object::new(ctx),
        pause: pausable::new(),
        roles: bridge_roles::new<BridgeSafeTag>(deployer, ctx),
        bridge_addr: deployer,
        batch_size: 10,
        batch_timeout_ms: DEFAULT_BATCH_TIMEOUT_MS,
        batch_settle_timeout_ms: DEFAULT_BATCH_SETTLE_TIMEOUT_MS,
        batches_count: 0,
        deposits_count: 0,
        token_cfg: table::new(ctx),
        batches: table::new(ctx),
        batch_deposits: table::new(ctx),
        coin_storage: bag::new(ctx),
        from_coin_cap,
    };

    transfer::public_transfer(bridge_cap, deployer);

    transfer::share_object(safe);
}

fun borrow_token_cfg_mut(safe: &mut BridgeSafe, key: vector<u8>): &mut TokenConfig {
    table::borrow_mut(&mut safe.token_cfg, key)
}

public fun whitelist_token<T>(
    safe: &mut BridgeSafe,
    minimum_amount: u64,
    maximum_amount: u64,
    is_native: bool,
    is_locked: bool,
    ctx: &mut TxContext,
) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let exists = table::contains(&safe.token_cfg, key);

    assert!(minimum_amount > 0, EZeroAmount);
    assert!(minimum_amount <= maximum_amount, EInvalidTokenLimits);

    if (exists) {
        let cfg = table::borrow(&safe.token_cfg, key);
        let is_currently_whitelisted = shared_structs::token_config_whitelisted(cfg);
        assert!(!is_currently_whitelisted, ETokenAlreadyExists);

        let cfg_mut = borrow_token_cfg_mut(safe, key);
        shared_structs::set_token_config_whitelisted(cfg_mut, true);
        shared_structs::set_token_config_is_native(cfg_mut, is_native);
        shared_structs::set_token_config_min_limit(cfg_mut, minimum_amount);
        shared_structs::set_token_config_max_limit(cfg_mut, maximum_amount);
        shared_structs::set_token_config_is_locked(cfg_mut, is_locked);
    } else {
        let cfg = shared_structs::create_token_config(
            true,
            is_native,
            minimum_amount,
            maximum_amount,
            is_locked,
        );
        table::add(&mut safe.token_cfg, key, cfg);
    };

    events::emit_token_whitelisted(
        key,
        minimum_amount,
        maximum_amount,
        is_native,
        false,
        is_locked,
    );
}

public fun remove_token_from_whitelist<T>(safe: &mut BridgeSafe, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    shared_structs::set_token_config_whitelisted(cfg, false);

    events::emit_token_removed_from_whitelist(key);
}

public fun is_token_whitelisted<T>(safe: &BridgeSafe): bool {
    let key = utils::type_name_bytes<T>();
    if (!table::contains(&safe.token_cfg, key)) {
        return false
    };
    let cfg = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_whitelisted(cfg)
}

public fun set_batch_timeout_ms(safe: &mut BridgeSafe, new_timeout_ms: u64, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(new_timeout_ms <= safe.batch_settle_timeout_ms, EBatchBlockLimitExceedsSettle);
    safe.batch_timeout_ms = new_timeout_ms;
}

public fun set_batch_settle_timeout_ms(
    safe: &mut BridgeSafe,
    new_timeout_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    pausable::assert_paused(&safe.pause);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(new_timeout_ms >= safe.batch_timeout_ms, EBatchSettleLimitBelowBlock);
    assert!(!is_any_batch_in_progress_internal(safe, clock), EBatchInProgress);
    safe.batch_settle_timeout_ms = new_timeout_ms;
}

public fun set_batch_size(safe: &mut BridgeSafe, new_size: u16, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(new_size > 0, EBatchSizeZero);
    assert!(new_size <= 100, EBatchSizeTooLarge);
    safe.batch_size = new_size;
}

public fun set_token_min_limit<T>(safe: &mut BridgeSafe, amount: u64, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    let old_max = shared_structs::token_config_max_limit(cfg);

    assert!(amount > 0, EZeroAmount);
    assert!(amount <= old_max, EInvalidTokenLimits);

    shared_structs::set_token_config_min_limit(cfg, amount);

    events::emit_token_limits_updated(key, amount, old_max);
}

public fun get_token_min_limit<T>(safe: &BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    let cfg = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_min_limit(cfg)
}

public(package) fun roles_mut(safe: &mut BridgeSafe): &mut Roles<BridgeSafeTag> {
    &mut safe.roles
}

public fun set_token_max_limit<T>(safe: &mut BridgeSafe, amount: u64, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    let old_min = shared_structs::token_config_min_limit(cfg);

    assert!(amount >= old_min, EInvalidTokenLimits);
    shared_structs::set_token_config_max_limit(cfg, amount);

    events::emit_token_limits_updated(key, old_min, amount);
}

public fun get_token_max_limit<T>(safe: &BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    let cfg = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_max_limit(cfg)
}

public fun get_token_is_mint_burn<T>(safe: &BridgeSafe): bool {
    let key = utils::type_name_bytes<T>();
    let cfg = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_is_mint_burn(cfg)
}

public fun get_token_is_native<T>(safe: &BridgeSafe): bool {
    let key = utils::type_name_bytes<T>();
    let cfg = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_is_native(cfg)
}

public fun set_token_is_native<T>(safe: &mut BridgeSafe, is_native: bool, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    shared_structs::set_token_config_is_native(cfg, is_native);

    events::emit_token_is_native_updated(key, is_native);
}

public fun set_token_is_locked<T>(safe: &mut BridgeSafe, is_locked: bool, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    shared_structs::set_token_config_is_locked(cfg, is_locked);

    events::emit_token_is_locked_updated(key, is_locked);
}

public fun set_token_is_mint_burn<T>(
    safe: &mut BridgeSafe,
    is_mint_burn: bool,
    ctx: &mut TxContext,
) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    shared_structs::set_token_config_is_mint_burn(cfg, is_mint_burn);

    events::emit_token_is_mint_burn_updated(key, is_mint_burn);
}

public fun set_bridge_addr(
    safe: &mut BridgeSafe,
    new_bridge_addr: address,
    ctx: &TxContext,
) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let previous_bridge = safe.bridge_addr;
    safe.bridge_addr = new_bridge_addr;
    events::emit_bridge_transferred(previous_bridge, new_bridge_addr);
}

public fun init_supply<T>(safe: &mut BridgeSafe, coin_in: Coin<T>, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

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
public fun deposit<T>(
    safe: &mut BridgeSafe,
    coin_in: Coin<T>,
    recipient: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    pausable::assert_not_paused(&safe.pause);

    assert!(vector::length(&recipient) == 32, EInvalidRecipient);

    let key = utils::type_name_bytes<T>();
    let cfg_ref = table::borrow(&safe.token_cfg, key);
    assert!(shared_structs::token_config_whitelisted(cfg_ref), ETokenNotWhitelisted);

    let amount = coin::value(&coin_in);
    assert!(amount > 0, EZeroAmount);
    assert!(amount >= shared_structs::token_config_min_limit(cfg_ref), EAmountBelowMinimum);
    assert!(amount <= shared_structs::token_config_max_limit(cfg_ref), EAmountAboveMaximum);

    if (should_create_new_batch_internal(safe, clock)) {
        create_new_batch_internal(safe, clock, ctx);
    };
    let batch_index = safe.batches_count - 1;
    let batch = table::borrow_mut(&mut safe.batches, batch_index);

    assert!(safe.deposits_count < MAX_U64, EOverflow);
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
    shared_structs::set_batch_last_updated_timestamp_ms(batch, clock::timestamp_ms(clock));

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

public(package) fun checkOwnerRole(safe: &BridgeSafe, ctx: &TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
}

public fun get_batch(safe: &BridgeSafe, batch_nonce: u64, clock: &Clock): (Batch, bool) {
    assert!(batch_nonce > 0, EBatchNotFound);
    let batch_index = batch_nonce - 1;

    if (!table::contains(&safe.batches, batch_index)) {
        let empty_batch = shared_structs::create_batch(0, 0);
        return (empty_batch, false)
    };

    let batch = *table::borrow(&safe.batches, batch_index);
    let is_final = is_batch_final_internal(safe, &batch, clock);
    (batch, is_final)
}

public fun get_deposits(
    safe: &BridgeSafe,
    batch_nonce: u64,
    clock: &Clock,
): (vector<Deposit>, bool) {
    assert!(batch_nonce > 0, EBatchNotFound);
    let batch_index = batch_nonce - 1;
    let deposits = if (table::contains(&safe.batch_deposits, batch_index)) {
        *table::borrow(&safe.batch_deposits, batch_index)
    } else {
        vector::empty()
    };
    if (!table::contains(&safe.batches, batch_index)) {
        return (deposits, false)
    };

    let batch = table::borrow(&safe.batches, batch_index);
    let is_final = is_batch_final_internal(safe, batch, clock);
    (deposits, is_final)
}

public fun is_any_batch_in_progress(safe: &BridgeSafe, clock: &Clock): bool {
    is_any_batch_in_progress_internal(safe, clock)
}

fun create_new_batch_internal(safe: &mut BridgeSafe, clock: &Clock, _ctx: &mut TxContext) {
    assert!(safe.batches_count < MAX_U64, EOverflow);
    let nonce = safe.batches_count + 1;
    let batch = shared_structs::create_batch(nonce, clock::timestamp_ms(clock));
    table::add(&mut safe.batches, safe.batches_count, batch);
    safe.batches_count = nonce;
}

fun should_create_new_batch_internal(safe: &BridgeSafe, clock: &Clock): bool {
    if (safe.batches_count == 0) { return true };
    let last_index = safe.batches_count - 1;
    let batch = table::borrow(&safe.batches, last_index);
    is_batch_progress_over_internal(safe, shared_structs::batch_deposits_count(batch), shared_structs::batch_timestamp_ms(batch), clock) || (shared_structs::batch_deposits_count(batch) >= safe.batch_size)
}

fun is_batch_progress_over_internal(
    safe: &BridgeSafe,
    dep_count: u16,
    timestamp_ms: u64,
    clock: &Clock,
): bool {
    if (dep_count == 0) { return false };
    (timestamp_ms + safe.batch_timeout_ms) <= clock::timestamp_ms(clock)
}

fun is_batch_final_internal(safe: &BridgeSafe, batch: &Batch, clock: &Clock): bool {
    (shared_structs::batch_last_updated_timestamp_ms(batch) + safe.batch_settle_timeout_ms) <= clock::timestamp_ms(clock)
}

fun is_any_batch_in_progress_internal(safe: &BridgeSafe, clock: &Clock): bool {
    if (safe.batches_count == 0) { return false };
    let last_index = safe.batches_count - 1;
    if (!should_create_new_batch_internal(safe, clock)) { return true };
    let batch = table::borrow(&safe.batches, last_index);
    !is_batch_final_internal(safe, batch, clock)
}

public fun get_bridge_addr(safe: &BridgeSafe): address {
    safe.bridge_addr
}

/// Get the current owner address
public fun get_owner(safe: &BridgeSafe): address {
    bridge_roles::owner(&safe.roles)
}

/// Get the pending owner address (if any)
public fun get_pending_owner(safe: &BridgeSafe): Option<address> {
    bridge_roles::pending_owner(&safe.roles)
}

public fun get_batch_size(safe: &BridgeSafe): u16 {
    safe.batch_size
}

public fun get_batch_timeout_ms(safe: &BridgeSafe): u64 {
    safe.batch_timeout_ms
}

public fun get_batch_settle_timeout_ms(safe: &BridgeSafe): u64 {
    safe.batch_settle_timeout_ms
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
/// Only the bridge role can call this function
/// The coins are taken from the contract's storage and sent to recipient
public(package) fun transfer<T>(
    safe: &mut BridgeSafe,
    _bridge_cap: &bridge_roles::BridgeCap,
    receiver: address,
    amount: u64,
    treasury: &mut treasury::Treasury<BRIDGE_TOKEN>,
    ctx: &mut TxContext,
): bool {
    let key = utils::type_name_bytes<T>();

    if (!table::contains(&safe.token_cfg, key)) {
        return false
    };

    let cfg_ref = table::borrow(&safe.token_cfg, key);

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

    if (!shared_structs::get_token_config_is_locked(cfg_ref)) {
        transfer::public_transfer(coin_to_transfer, receiver);
    } else {
        transfer::public_transfer(coin_to_transfer, @0x0);
        let stored_bt_coin = bag::borrow_mut<
            vector<u8>,
            Coin<locked_token::bridge_token::BRIDGE_TOKEN>,
        >(
            &mut safe.coin_storage,
            key,
        );
        let coin_bt = coin::split(stored_bt_coin, amount, ctx);

        treasury::transfer_from_coin<locked_token::bridge_token::BRIDGE_TOKEN>(
            treasury,
            receiver,
            &safe.from_coin_cap,
            coin_bt,
            ctx,
        );
    };

    let cfg_mut = borrow_token_cfg_mut(safe, key);
    shared_structs::subtract_from_token_config_total_balance(cfg_mut, amount);

    true
}

public fun get_stored_coin_balance<T>(safe: &mut BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    if (!table::contains(&safe.token_cfg, key)) {
        return 0
    };
    let cfg_ref = table::borrow(&safe.token_cfg, key);
    shared_structs::token_config_total_balance(cfg_ref)
}

public fun pause_contract(safe: &mut BridgeSafe, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    pausable::pause(&mut safe.pause);
}

public fun unpause_contract(safe: &mut BridgeSafe, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    pausable::unpause(&mut safe.pause);
}

public fun transfer_ownership(safe: &mut BridgeSafe, new_owner: address, ctx: &TxContext) {
    safe.roles_mut().owner_role_mut().begin_role_transfer(new_owner, ctx)
}

public fun accept_ownership(safe: &mut BridgeSafe, ctx: &TxContext) {
    safe.roles_mut().owner_role_mut().accept_role(ctx)
}

#[test_only]
public fun init_for_testing(from_cap: treasury::FromCoinCap<BRIDGE_TOKEN>, ctx: &mut TxContext) {
    initialize(from_cap, ctx);
}

#[test_only]
public fun create_batch_for_testing(safe: &mut BridgeSafe, clock: &Clock, ctx: &mut TxContext) {
    create_new_batch_internal(safe, clock, ctx);
}
