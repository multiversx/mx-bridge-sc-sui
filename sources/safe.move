/// Safe Module - Token Management ani Batch Processing
///
/// This module manages token deposits, batching, and secure transfers.
/// It handles whitelisting, token limits, and coordinates with the bridge module.

module bridge_safe::safe;

use bridge_safe::bridge_roles::{Self, Roles, BridgeSafeTag};
use bridge_safe::bridge_version_control;
use bridge_safe::events;
use bridge_safe::pausable::{Self, Pause};
use bridge_safe::upgrade_service_bridge;
use bridge_safe::utils;
use locked_token::bridge_token::BRIDGE_TOKEN;
use locked_token::treasury::{Self as lkt};
use bridge_safe::shared_structs::{Self, TokenConfig, Batch, Deposit};
use std::u64::{min, max};
use sui::bag::{Self, Bag};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

// === Migration Events ===

public struct MigrationStarted has copy, drop {
    compatible_versions: vector<u64>,
}

public struct MigrationAborted has copy, drop {
    compatible_versions: vector<u64>,
}

public struct MigrationCompleted has copy, drop {
    compatible_versions: vector<u64>,
}

// === Error Constants ===
const ETokenAlreadyExists: u64 = 0;
const EBatchBlockLimitExceedsSettle: u64 = 1;
const EBatchSettleLimitBelowBlock: u64 = 2;
const EBatchInProgress: u64 = 3;
const EBatchSizeTooLarge: u64 = 4;
const ETokenNotWhitelisted: u64 = 5;
const EAmountBelowMinimum: u64 = 6;
const EAmountAboveMaximum: u64 = 7;
const EInsufficientBalance: u64 = 8;
const EInvalidRecipient: u64 = 9;
const EZeroAmount: u64 = 10;
const EOverflow: u64 = 11;
const EBatchNotFound: u64 = 12;
const EBatchSizeZero: u64 = 13;
const EObjectMigrated: u64 = 14;
const EInvalidTokenLimits: u64 = 15;
const EMigrationStarted: u64 = 16;
const EMigrationNotStarted: u64 = 17;
const ENotPendingVersion: u64 = 18;
const ENotNativeToken: u64 = 19;
const EIncompatibleTokenFlags: u64 = 22;
const EUnauthorizedBridgeCap: u64 = 23;

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
    from_coin_cap: lkt::FromCoinCap<BRIDGE_TOKEN>,
    compatible_versions: VecSet<u64>,
}

/// One-time capability minted in init and consumed in initialize.
public struct SafeInitCap has key {
    id: UID,
}

public struct SAFE has drop {}

fun init(witness: SAFE, ctx: &mut TxContext) {
    let (upgrade_service, _witness) = upgrade_service_bridge::new(
        witness,
        ctx.sender(),
        ctx,
    );

    transfer::transfer(SafeInitCap { id: object::new(ctx) }, ctx.sender());

    // Share the upgrade service object
    transfer::public_share_object(upgrade_service);
}

#[allow(lint(self_transfer))]
public fun initialize(init_cap: SafeInitCap, from_coin_cap: lkt::FromCoinCap<BRIDGE_TOKEN>, ctx: &mut TxContext) {
    let SafeInitCap { id } = init_cap;
    object::delete(id);

    let deployer = ctx.sender();
    let safe_uid = object::new(ctx);
    let safe_id = object::uid_to_inner(&safe_uid);

    let w = bridge_roles::grant_witness();
    let bridge_cap = w.publish_caps(safe_id, ctx);

    let safe = BridgeSafe {
        id: safe_uid,
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
        compatible_versions: vec_set::singleton(bridge_version_control::current_version()),
    };

    transfer::public_transfer(bridge_cap, deployer);
    transfer::share_object(safe);
}

/// Deposit function for native tokens: coin is stored in the safe's coin_storage bag.
public fun deposit<T>(
    safe: &mut BridgeSafe,
    coin_in: Coin<T>,
    recipient: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_is_compatible(safe);
    let (key, amount, batch_nonce, dep_nonce) = deposit_validate_and_record<T>(
        safe,
        &coin_in,
        recipient,
        false,
        clock,
        ctx,
    );

    if (safe.coin_storage.contains(key)) {
        safe.coin_storage.borrow_mut<vector<u8>, Coin<T>>(key).join(coin_in);
    } else {
        safe.coin_storage.add(key, coin_in);
    };

    events::emit_deposit_v1(
        batch_nonce,
        dep_nonce,
        ctx.sender(),
        recipient,
        amount,
        key,
    );
}

/// Transfer function for native tokens: splits coin from the safe's bag and sends to receiver.
/// Only the bridge role can call this function.
public(package) fun transfer<T>(
    safe: &mut BridgeSafe,
    bridge_cap: &bridge_roles::BridgeCap,
    receiver: address,
    amount: u64,
    treasury: &mut lkt::Treasury<BRIDGE_TOKEN>,
    ctx: &mut TxContext,
): bool {
    assert!(bridge_roles::bridge_cap_safe_id(bridge_cap) == object::uid_to_inner(&safe.id), EUnauthorizedBridgeCap);
    let key = utils::type_name_bytes<T>();

    if (!safe.token_cfg.contains(key)) {
        return false
    };

    let (is_mint_burn, current_balance, is_locked) = {
        let cfg_ref = safe.token_cfg.borrow(key);
        (cfg_ref.token_config_is_mint_burn(), cfg_ref.token_config_total_balance(), cfg_ref.get_token_config_is_locked())
    };

    if (is_mint_burn) {
        return false
    };

    if (current_balance < amount) {
        return false
    };

    if (!safe.coin_storage.contains(key)) {
        return false
    };

    if (!is_locked) {
        let stored_coin = safe.coin_storage.borrow_mut<vector<u8>, Coin<T>>(key);
        let coin_value = stored_coin.value();
        if (coin_value < amount) {
            return false
        };

        let coin_to_transfer = stored_coin.split(amount, ctx);

        if (stored_coin.value() == 0) {
            let empty_coin = safe.coin_storage.remove<vector<u8>, Coin<T>>(key);
            empty_coin.destroy_zero();
        };

        transfer::public_transfer(coin_to_transfer, receiver);
    
    } else {
        let stored_bt_coin = safe.coin_storage.borrow_mut<vector<u8>, Coin<BRIDGE_TOKEN>>(key);

        let coin_value = stored_bt_coin.value();
        if (coin_value < amount) {
            return false
        };

        let coin_bt = stored_bt_coin.split(amount, ctx);
        if (stored_bt_coin.value() == 0) {
            let empty_coin = safe.coin_storage.remove<vector<u8>, Coin<BRIDGE_TOKEN>>(
                key,
            );
            empty_coin.destroy_zero();
        };
        lkt::transfer_from_coin<BRIDGE_TOKEN>(
            treasury,
            receiver,
            &safe.from_coin_cap,
            coin_bt,
            ctx,
        );
    };

    let cfg_mut = borrow_token_cfg_mut(safe, key);
    cfg_mut.subtract_from_token_config_total_balance(amount);

    true
}

public fun is_token_whitelisted<T>(safe: &BridgeSafe): bool {
    let key = utils::type_name_bytes<T>();
    if (!safe.token_cfg.contains(key)) {
        return false
    };
    let cfg = safe.token_cfg.borrow(key);
    cfg.token_config_whitelisted()
}

public fun get_token_min_limit<T>(safe: &BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    let cfg = safe.token_cfg.borrow(key);
    cfg.token_config_min_limit()
}

public fun get_token_max_limit<T>(safe: &BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    let cfg = safe.token_cfg.borrow(key);
    cfg.token_config_max_limit()
}

public fun get_token_is_mint_burn<T>(safe: &BridgeSafe): bool {
    let key = utils::type_name_bytes<T>();
    let cfg = safe.token_cfg.borrow(key);
    cfg.token_config_is_mint_burn()
}

public fun get_token_is_native<T>(safe: &BridgeSafe): bool {
    let key = utils::type_name_bytes<T>();
    let cfg = safe.token_cfg.borrow(key);
    cfg.token_config_is_native()
}

public fun get_batch(safe: &BridgeSafe, batch_nonce: u64, clock: &Clock): (Batch, bool) {
    assert!(batch_nonce > 0, EBatchNotFound);
    let batch_index = batch_nonce - 1;

    if (!safe.batches.contains(batch_index)) {
        let empty_batch = shared_structs::create_batch(0, 0);
        return (empty_batch, false)
    };

    let batch = *safe.batches.borrow(batch_index);
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
    let deposits = if (safe.batch_deposits.contains(batch_index)) {
        *safe.batch_deposits.borrow(batch_index)
    } else {
        vector[]
    };
    if (!safe.batches.contains(batch_index)) {
        return (deposits, false)
    };

    let batch = safe.batches.borrow(batch_index);
    let is_final = is_batch_final_internal(safe, batch, clock);
    (deposits, is_final)
}

public fun is_any_batch_in_progress(safe: &BridgeSafe, clock: &Clock): bool {
    is_any_batch_in_progress_internal(safe, clock)
}

public fun get_bridge_addr(safe: &BridgeSafe): address {
    safe.bridge_addr
}

/// Get the current owner address
public fun get_owner(safe: &BridgeSafe): address {
    safe.roles.owner()
}

/// Get the pending owner address (if any)
public fun get_pending_owner(safe: &BridgeSafe): Option<address> {
    safe.roles.pending_owner()
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

public(package) fun get_pause_mut(safe: &mut BridgeSafe): &mut Pause {
    &mut safe.pause
}

public fun get_batch_nonce(batch: &Batch): u64 {
    batch.batch_nonce()
}

public fun get_batch_deposits_count(batch: &Batch): u16 {
    batch.batch_deposits_count()
}

public fun get_stored_coin_balance<T>(safe: &mut BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    if (!safe.token_cfg.contains(key)) {
        return 0
    };
    let cfg_ref = safe.token_cfg.borrow(key);
    cfg_ref.token_config_total_balance()
}

public fun get_coin_storage_balance<T>(safe: &BridgeSafe): u64 {
    let key = utils::type_name_bytes<T>();
    if (!safe.coin_storage.contains(key)) {
        return 0
    };
    let stored_coin = safe.coin_storage.borrow<vector<u8>, Coin<T>>(key);
    stored_coin.value()
}

// === Admin Management ===

public fun pause_contract(safe: &mut BridgeSafe, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    safe.pause.pause();
}

public fun unpause_contract(safe: &mut BridgeSafe, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    safe.pause.unpause();
}

public fun transfer_ownership(safe: &mut BridgeSafe, new_owner: address, ctx: &TxContext) {
    assert_is_compatible(safe);
    safe.roles_mut().owner_role_mut().begin_role_transfer(new_owner, ctx)
}

public fun accept_ownership(safe: &mut BridgeSafe, ctx: &TxContext) {
    assert_is_compatible(safe);
    safe.roles_mut().owner_role_mut().accept_role(ctx)
}

public fun init_supply<T>(safe: &mut BridgeSafe, coin_in: Coin<T>, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();

    assert_token_is_whitelisted(safe, key);
    let cfg_ref = safe.token_cfg.borrow(key);
    assert!(cfg_ref.token_config_is_native(), ENotNativeToken);

    let amount = coin::value(&coin_in);

    let cfg_mut = borrow_token_cfg_mut(safe, key);
    cfg_mut.add_to_token_config_total_balance(amount);

    if (safe.coin_storage.contains(key)) {
        let existing_coin = safe.coin_storage.borrow_mut<vector<u8>, Coin<T>>(key);
        existing_coin.join(coin_in);
    } else {
        safe.coin_storage.add(key, coin_in);
    };
}

#[allow(lint(self_transfer))]
public fun sync_supply<T>(safe: &mut BridgeSafe, mut coin_in: Coin<T>, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();

    assert_token_is_whitelisted(safe, key);
    let cfg_ref = safe.token_cfg.borrow(key);
    assert!(cfg_ref.token_config_is_native(), ENotNativeToken);

    let expected_balance = cfg_ref.token_config_total_balance();

    let actual_balance = if (safe.coin_storage.contains(key)) {
        let stored_coin = safe.coin_storage.borrow<vector<u8>, Coin<T>>(key);
        stored_coin.value()
    } else {
        0
    };

    assert!(expected_balance > actual_balance, EInsufficientBalance);

    let deficit = expected_balance - actual_balance;
    assert!(coin_in.value() >= deficit, EInsufficientBalance);

    let top_up_coin = coin_in.split(deficit, ctx);

    if (safe.coin_storage.contains(key)) {
        let existing_coin = safe.coin_storage.borrow_mut<vector<u8>, Coin<T>>(key);
        existing_coin.join(top_up_coin);
    } else {
        safe.coin_storage.add(key, top_up_coin);
    };

    if (coin_in.value() == 0) {
        coin_in.destroy_zero();
    } else {
        transfer::public_transfer(coin_in, ctx.sender());
    };
}

public fun whitelist_token<T>(
    safe: &mut BridgeSafe,
    minimum_amount: u64,
    maximum_amount: u64,
    is_locked: bool,
    ctx: &mut TxContext,
) {
    assert_is_compatible(safe);
    whitelist_token_internal<T>(
        safe,
        minimum_amount,
        maximum_amount,
        true,
        option::none(),
        false,
        is_locked,
        ctx,
    );
}

/// Removes a native (non-mint-burn) token from the whitelist.
/// For mint-burn tokens, use the adapter's remove_token_from_whitelist instead.
public fun remove_token_from_whitelist<T>(safe: &mut BridgeSafe, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    let key = utils::type_name_bytes<T>();
    let cfg_ref = safe.token_cfg.borrow(key);
    assert!(!cfg_ref.token_config_is_mint_burn(), EIncompatibleTokenFlags);
    unwhitelist_token(safe, key);
}

/// Package-internal: marks a token as not whitelisted without the mint-burn guard.
/// Used by the adapter which handles MintCap cleanup separately.
public(package) fun unwhitelist_token(safe: &mut BridgeSafe, key: vector<u8>) {
    let cfg = borrow_token_cfg_mut(safe, key);
    cfg.set_token_config_whitelisted(false);
    events::emit_token_removed_from_whitelist(key);
}

public fun set_bridge_addr(safe: &mut BridgeSafe, new_bridge_addr: address, ctx: &TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let previous_bridge = safe.bridge_addr;
    safe.bridge_addr = new_bridge_addr;
    events::emit_bridge_transferred(previous_bridge, new_bridge_addr);
}

public fun set_batch_timeout_ms(safe: &mut BridgeSafe, new_timeout_ms: u64, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(new_timeout_ms <= safe.batch_settle_timeout_ms, EBatchBlockLimitExceedsSettle);
    safe.batch_timeout_ms = new_timeout_ms;
    events::emit_batch_timeout_updated(new_timeout_ms);
}

public fun set_batch_settle_timeout_ms(
    safe: &mut BridgeSafe,
    new_timeout_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_is_compatible(safe);
    safe.pause.assert_paused();
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(new_timeout_ms >= safe.batch_timeout_ms, EBatchSettleLimitBelowBlock);
    assert!(!is_any_batch_in_progress_internal(safe, clock), EBatchInProgress);
    safe.batch_settle_timeout_ms = new_timeout_ms;
    events::emit_batch_settle_timeout_updated(new_timeout_ms);
}

public fun set_batch_size(safe: &mut BridgeSafe, new_size: u16, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(new_size > 0, EBatchSizeZero);
    assert!(new_size <= 100, EBatchSizeTooLarge);
    safe.batch_size = new_size;
    events::emit_batch_size_updated(new_size);
}

public fun set_token_min_limit<T>(safe: &mut BridgeSafe, amount: u64, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    let old_max = cfg.token_config_max_limit();

    assert!(amount > 0, EZeroAmount);
    assert!(amount <= old_max, EInvalidTokenLimits);

    cfg.set_token_config_min_limit(amount);

    events::emit_token_limits_updated(key, amount, old_max);
}

public fun set_token_max_limit<T>(safe: &mut BridgeSafe, amount: u64, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    let old_min = cfg.token_config_min_limit();

    assert!(amount >= old_min, EInvalidTokenLimits);
    cfg.set_token_config_max_limit(amount);

    events::emit_token_limits_updated(key, old_min, amount);
}

public fun set_token_is_native<T>(safe: &mut BridgeSafe, is_native: bool, ctx: &mut TxContext) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    assert!(!(is_native && cfg.token_config_is_mint_burn()), EIncompatibleTokenFlags);
    cfg.set_token_config_is_native(is_native);

    events::emit_token_is_native_updated(key, is_native);
}

public fun set_token_is_mint_burn<T>(
    safe: &mut BridgeSafe,
    is_mint_burn: bool,
    ctx: &mut TxContext,
) {
    assert_is_compatible(safe);
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    assert!(!(is_mint_burn && cfg.token_config_is_native()), EIncompatibleTokenFlags);
    cfg.set_token_config_is_mint_burn(is_mint_burn);

    events::emit_token_is_mint_burn_updated(key, is_mint_burn);
}

public fun set_token_is_locked<T>(safe: &mut BridgeSafe, is_locked: bool, ctx: &mut TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    let key = utils::type_name_bytes<T>();
    let cfg = borrow_token_cfg_mut(safe, key);
    assert!(
        !(is_locked && shared_structs::token_config_is_mint_burn(cfg)),
        EIncompatibleTokenFlags,
    );
    shared_structs::set_token_config_is_locked(cfg, is_locked);

    events::emit_token_is_locked_updated(key, is_locked);
}

// === Upgrade Management ===

/// Returns the compatible versions for the safe
public fun compatible_versions(safe: &BridgeSafe): vector<u64> {
    *safe.compatible_versions.keys()
}

/// Returns the current active version (lowest version in the set)
public fun current_active_version(safe: &BridgeSafe): u64 {
    let versions = safe.compatible_versions.keys();
    if (versions.length() == 1) {
        versions[0]
    } else {
        min(versions[0], versions[1])
    }
}

/// Returns the pending version if migration is in progress, otherwise returns none
public fun pending_version(safe: &BridgeSafe): Option<u64> {
    if (safe.compatible_versions.length() == 2) {
        let versions = safe.compatible_versions.keys();
        option::some(max(versions[0], versions[1]))
    } else {
        option::none()
    }
}

/// Starts the migration process, making the Safe object be
/// additionally compatible with this package's version.
public fun start_migration(safe: &mut BridgeSafe, ctx: &TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(safe.compatible_versions.length() == 1, EMigrationStarted);

    let active_version = safe.compatible_versions.keys()[0];
    assert!(active_version < bridge_version_control::current_version(), EObjectMigrated);

    safe.compatible_versions.insert(bridge_version_control::current_version());

    event::emit(MigrationStarted {
        compatible_versions: *safe.compatible_versions.keys(),
    });
}

/// Aborts the migration process, reverting the Safe object's compatibility
/// to the previous version.
public fun abort_migration(safe: &mut BridgeSafe, ctx: &TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(safe.compatible_versions.length() == 2, EMigrationNotStarted);

    let pending_version = max(
        safe.compatible_versions.keys()[0],
        safe.compatible_versions.keys()[1],
    );
    assert!(pending_version == bridge_version_control::current_version(), ENotPendingVersion);

    safe.compatible_versions.remove(&pending_version);

    event::emit(MigrationAborted {
        compatible_versions: *safe.compatible_versions.keys(),
    });
}

/// Completes the migration process, making the Safe object be
/// only compatible with this package's version.
public fun complete_migration(safe: &mut BridgeSafe, ctx: &TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(safe.compatible_versions.length() == 2, EMigrationNotStarted);

    let (version_a, version_b) = (
        safe.compatible_versions.keys()[0],
        safe.compatible_versions.keys()[1],
    );
    let (active_version, pending_version) = (min(version_a, version_b), max(version_a, version_b));

    assert!(pending_version == bridge_version_control::current_version(), ENotPendingVersion);

    safe.compatible_versions.remove(&active_version);

    event::emit(MigrationCompleted {
        compatible_versions: *safe.compatible_versions.keys(),
    });
}

/// Helper function to check if a migration is in progress
public fun is_migration_in_progress(safe: &BridgeSafe): bool {
    safe.compatible_versions.length() > 1
}

// === Asserts ===

public(package) fun assert_is_compatible(safe: &BridgeSafe) {
    bridge_version_control::assert_object_version_is_compatible_with_package(safe.compatible_versions);
}

public(package) fun assert_token_is_whitelisted(safe: &BridgeSafe, key: vector<u8>) {
    assert!(safe.token_cfg.contains(key), ETokenNotWhitelisted);
    let cfg = safe.token_cfg.borrow(key);
    assert!(cfg.token_config_whitelisted(), ETokenNotWhitelisted);
}

public(package) fun assert_token_is_not_whitelisted(safe: &BridgeSafe, key: vector<u8>) {
    assert!(safe.token_cfg.contains(key), ETokenNotWhitelisted);
    let cfg = safe.token_cfg.borrow(key);
    assert!(!cfg.token_config_whitelisted(), ETokenAlreadyExists);
}

public(package) fun assert_token_is_mint_burn(safe: &BridgeSafe, key: vector<u8>) {
    assert!(safe.token_cfg.contains(key), ETokenNotWhitelisted);
    let cfg = safe.token_cfg.borrow(key);
    assert!(cfg.token_config_is_mint_burn(), EIncompatibleTokenFlags);
}

/// ==== Internal logic helpers ====

public(package) fun whitelist_token_internal<T>(
    safe: &mut BridgeSafe,
    minimum_amount: u64,
    maximum_amount: u64,
    is_native: bool,
    treasury_id: Option<ID>,
    is_mint_burn: bool,
    is_locked: bool,
    ctx: &TxContext,
) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);

    assert!(!(is_mint_burn && is_locked), EIncompatibleTokenFlags);
    assert!(minimum_amount > 0, EZeroAmount);
    assert!(minimum_amount <= maximum_amount, EInvalidTokenLimits);

    let key = utils::type_name_bytes<T>();
    let exists = safe.token_cfg.contains(key);
    if (exists) {
        assert_token_is_not_whitelisted(safe, key);
    };

    shared_structs::upsert_token_config(
        &mut safe.token_cfg,
        key,
        true,
        is_native,
        minimum_amount,
        maximum_amount,
        treasury_id,
        is_mint_burn,
        is_locked,
    );

    events::emit_token_whitelisted(
        key,
        minimum_amount,
        maximum_amount,
        is_native,
        is_mint_burn,
        is_locked,
    );
}

/// Shared helper: validates deposit preconditions, manages batching, records the deposit,
/// and updates the token balance. Returns (key, amount, batch_nonce, dep_nonce).
/// `expect_mint_burn` drives the variant guard: false for native, true for mint-burn.
public(package) fun deposit_validate_and_record<T>(
    safe: &mut BridgeSafe,
    coin_in: &Coin<T>,
    recipient: vector<u8>,
    expect_mint_burn: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): (vector<u8>, u64, u64, u64) {
    safe.pause.assert_not_paused();
    assert!(recipient.length() == 32, EInvalidRecipient);

    let key = utils::type_name_bytes<T>();
    let cfg_ref = safe.token_cfg.borrow(key);
    assert!(cfg_ref.token_config_whitelisted(), ETokenNotWhitelisted);
    assert!(cfg_ref.token_config_is_mint_burn() == expect_mint_burn, EIncompatibleTokenFlags);

    let amount = coin_in.value();
    assert!(amount > 0, EZeroAmount);
    assert!(amount >= cfg_ref.token_config_min_limit(), EAmountBelowMinimum);
    assert!(amount <= cfg_ref.token_config_max_limit(), EAmountAboveMaximum);

    if (should_create_new_batch_internal(safe, clock)) {
        create_new_batch_internal(safe, clock, ctx);
    };

    let batch_index = safe.batches_count - 1;
    let batch = safe.batches.borrow_mut(batch_index);

    assert!(safe.deposits_count < MAX_U64, EOverflow);
    let dep_nonce = safe.deposits_count + 1;
    let dep = shared_structs::create_deposit(
        dep_nonce,
        key,
        amount,
        ctx.sender(),
        recipient,
    );

    if (!safe.batch_deposits.contains(batch_index)) {
        safe.batch_deposits.add(batch_index, vector[]);
    };
    let vec_ref = safe.batch_deposits.borrow_mut(batch_index);
    vec_ref.push_back(dep);

    safe.deposits_count = dep_nonce;
    batch.increment_batch_deposits();
    batch.set_batch_last_updated_timestamp_ms(clock.timestamp_ms());

    let batch_nonce = batch.batch_nonce();

    let cfg = borrow_token_cfg_mut(safe, key);
    cfg.add_to_token_config_total_balance(amount);

    (key, amount, batch_nonce, dep_nonce)
}

fun create_new_batch_internal(safe: &mut BridgeSafe, clock: &Clock, _ctx: &mut TxContext) {
    assert!(safe.batches_count < MAX_U64, EOverflow);
    let nonce = safe.batches_count + 1;
    let batch = shared_structs::create_batch(nonce, clock.timestamp_ms());
    safe.batches.add(safe.batches_count, batch);
    safe.batches_count = nonce;
}

fun should_create_new_batch_internal(safe: &BridgeSafe, clock: &Clock): bool {
    if (safe.batches_count == 0) { return true };
    let last_index = safe.batches_count - 1;
    let batch = safe.batches.borrow(last_index);
    is_batch_progress_over_internal(safe, batch.batch_deposits_count(), batch.batch_timestamp_ms(), clock) || (batch.batch_deposits_count() >= safe.batch_size)
}

fun is_batch_progress_over_internal(
    safe: &BridgeSafe,
    dep_count: u16,
    timestamp_ms: u64,
    clock: &Clock,
): bool {
    if (dep_count == 0) { return false };
    (timestamp_ms + safe.batch_timeout_ms) <= clock.timestamp_ms()
}

fun is_batch_final_internal(safe: &BridgeSafe, batch: &Batch, clock: &Clock): bool {
    (batch.batch_last_updated_timestamp_ms() + safe.batch_settle_timeout_ms) <= clock.timestamp_ms()
}

fun is_any_batch_in_progress_internal(safe: &BridgeSafe, clock: &Clock): bool {
    if (safe.batches_count == 0) { return false };
    let last_index = safe.batches_count - 1;
    if (!should_create_new_batch_internal(safe, clock)) { return true };
    let batch = safe.batches.borrow(last_index);
    !is_batch_final_internal(safe, batch, clock)
}

/// ==== Internal helpers ====

public(package) fun checkOwnerRole(safe: &BridgeSafe, ctx: &TxContext) {
    safe.roles.owner_role().assert_sender_is_active_role(ctx);
}

public(package) fun uid(safe: &BridgeSafe): &UID {
    &safe.id
}

public(package) fun uid_mut(safe: &mut BridgeSafe): &mut UID {
    &mut safe.id
}

public(package) fun has_token_config<T>(safe: &BridgeSafe): bool {
    safe.token_cfg.contains(utils::type_name_bytes<T>())
}

public(package) fun subtract_token_balance<T>(safe: &mut BridgeSafe, amount: u64) {
    let key = utils::type_name_bytes<T>();
    let cfg = safe.token_cfg.borrow_mut(key);
    cfg.subtract_from_token_config_total_balance(amount);
}

fun borrow_token_cfg_mut(safe: &mut BridgeSafe, key: vector<u8>): &mut TokenConfig {
    safe.token_cfg.borrow_mut(key)
}

public(package) fun roles_mut(safe: &mut BridgeSafe): &mut Roles<BridgeSafeTag> {
    &mut safe.roles
}

/// Test helper that performs a mint-burn deposit without calling the real treasury burn.
/// Validates all deposit rules and records the batch, but destroys the coin in-place
/// instead of burning via treasury. Use this to test deposit recording logic without
/// needing a fully configured stablecoin-sui treasury.
#[test_only]
public fun deposit_mint_burn_for_testing<T>(
    safe: &mut BridgeSafe,
    coin_in: Coin<T>,
    recipient: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    use sui::test_utils;
    let (key, amount, batch_nonce, dep_nonce) = deposit_validate_and_record<T>(
        safe,
        &coin_in,
        recipient,
        true,
        clock,
        ctx,
    );
    test_utils::destroy(coin_in);
    events::emit_deposit_v1(
        batch_nonce,
        dep_nonce,
        ctx.sender(),
        recipient,
        amount,
        key,
    );
}

#[test_only]
public fun init_for_testing(from_cap: lkt::FromCoinCap<BRIDGE_TOKEN>, ctx: &mut TxContext) {
    let init_cap = SafeInitCap { id: object::new(ctx) };
    initialize(init_cap, from_cap, ctx);
}

#[test_only]
public fun trigger_init_for_testing(ctx: &mut TxContext) {
    transfer::transfer(SafeInitCap { id: object::new(ctx) }, ctx.sender());
}

#[test_only]
public fun create_batch_for_testing(safe: &mut BridgeSafe, clock: &Clock, ctx: &mut TxContext) {
    create_new_batch_internal(safe, clock, ctx);
}

#[test_only]
public fun add_to_balance_for_testing<T>(safe: &mut BridgeSafe, amount: u64) {
    let key = utils::type_name_bytes<T>();
    let cfg_mut = borrow_token_cfg_mut(safe, key);
    cfg_mut.add_to_token_config_total_balance(amount);
}
