module bridge_safe::shared_structs;

use sui::table::Table;

const EUnderflow: u64 = 0;
const EOverflow: u64 = 1;
const MAX_U64: u64 = 18446744073709551615;

public enum DepositStatus has copy, drop, store {
    None,
    Pending,
    InProgress,
    Executed,
    Rejected,
}

public struct Deposit has copy, drop, store {
    nonce: u64,
    token_key: vector<u8>,
    amount: u64,
    sender: address,
    recipient: vector<u8>,
}

public struct CrossTransferStatus has copy, drop, store {
    statuses: vector<DepositStatus>,
    created_timestamp_ms: u64,
}

public struct Batch has copy, drop, store {
    nonce: u64,
    timestamp_ms: u64,
    last_updated_timestamp_ms: u64,
    deposits_count: u16,
}

public struct TokenConfig has copy, drop, store {
    whitelisted: bool,
    is_native: bool,
    is_mint_burn: bool,
    min_limit: u64,
    max_limit: u64,
    total_balance: u64,
    treasury_id: Option<ID>,
    is_locked: bool,
}

public struct AdminRole has key {
    id: UID,
}

public fun create_deposit(
    nonce: u64,
    token_key: vector<u8>,
    amount: u64,
    sender: address,
    recipient: vector<u8>,
): Deposit {
    Deposit {
        nonce,
        token_key,
        amount,
        sender,
        recipient,
    }
}

public fun create_batch(nonce: u64, timestamp_ms: u64): Batch {
    Batch {
        nonce,
        timestamp_ms,
        last_updated_timestamp_ms: timestamp_ms,
        deposits_count: 0,
    }
}

public fun create_cross_transfer_status(
    statuses: vector<DepositStatus>,
    created_timestamp_ms: u64,
): CrossTransferStatus {
    CrossTransferStatus {
        statuses,
        created_timestamp_ms,
    }
}

public fun cross_transfer_status_statuses(status: &CrossTransferStatus): vector<DepositStatus> {
    status.statuses
}

public fun cross_transfer_status_created_timestamp_ms(status: &CrossTransferStatus): u64 {
    status.created_timestamp_ms
}

public fun deposit_status_executed(): DepositStatus {
    DepositStatus::Executed
}

public fun deposit_status_rejected(): DepositStatus {
    DepositStatus::Rejected
}

public(package) fun update_batch_last_updated(batch: &mut Batch, timestamp_ms: u64) {
    batch.last_updated_timestamp_ms = timestamp_ms;
}

public(package) fun increment_batch_deposits(batch: &mut Batch) {
    batch.deposits_count = batch.deposits_count + 1;
}

public fun token_config_whitelisted(config: &TokenConfig): bool {
    config.whitelisted
}

public fun token_config_min_limit(config: &TokenConfig): u64 {
    config.min_limit
}

public fun token_config_max_limit(config: &TokenConfig): u64 {
    config.max_limit
}

public fun token_config_total_balance(config: &TokenConfig): u64 {
    config.total_balance
}

public(package) fun set_token_config_whitelisted(config: &mut TokenConfig, whitelisted: bool) {
    config.whitelisted = whitelisted;
}

public(package) fun set_token_config_min_limit(config: &mut TokenConfig, min_limit: u64) {
    config.min_limit = min_limit;
}

public(package) fun set_token_config_max_limit(config: &mut TokenConfig, max_limit: u64) {
    config.max_limit = max_limit;
}

public(package) fun set_token_config_is_native(config: &mut TokenConfig, is_native: bool) {
    config.is_native = is_native;
}

public(package) fun set_token_config_is_mint_burn(config: &mut TokenConfig, is_mint_burn: bool) {
    config.is_mint_burn = is_mint_burn;
}

public fun token_config_treasury_id(config: &TokenConfig): Option<ID> {
    config.treasury_id
}

public(package) fun set_token_config_is_locked(config: &mut TokenConfig, is_locked: bool) {
    config.is_locked = is_locked;
}

public fun get_token_config_is_locked(config: &TokenConfig): bool {
    config.is_locked
}

public(package) fun add_to_token_config_total_balance(config: &mut TokenConfig, amount: u64) {
    assert!(config.total_balance <= MAX_U64 - amount, EOverflow);
    config.total_balance = config.total_balance + amount;
}

public(package) fun subtract_from_token_config_total_balance(
    config: &mut TokenConfig,
    amount: u64,
) {
    assert!(config.total_balance >= amount, EUnderflow);
    config.total_balance = config.total_balance - amount;
}

public fun token_config_is_native(config: &TokenConfig): bool {
    config.is_native
}

public fun token_config_is_mint_burn(config: &TokenConfig): bool {
    config.is_mint_burn
}

public fun batch_nonce(batch: &Batch): u64 {
    batch.nonce
}

public fun batch_deposits_count(batch: &Batch): u16 {
    batch.deposits_count
}

public fun batch_last_updated_timestamp_ms(batch: &Batch): u64 {
    batch.last_updated_timestamp_ms
}

public fun batch_timestamp_ms(batch: &Batch): u64 {
    batch.timestamp_ms
}

public(package) fun set_batch_deposits_count(batch: &mut Batch, count: u16) {
    batch.deposits_count = count;
}

public(package) fun set_batch_last_updated_timestamp_ms(batch: &mut Batch, timestamp_ms: u64) {
    batch.last_updated_timestamp_ms = timestamp_ms;
}

public(package) fun upsert_token_config(
    config: &mut Table<vector<u8>, TokenConfig>,
    key: vector<u8>,
    whitelisted: bool,
    is_native: bool,
    min_limit: u64,
    max_limit: u64,
    treasury_id: Option<ID>,
    is_mint_burn: bool,
    is_locked: bool
) {
    if (config.contains(key)) {
        let cfg = config.borrow_mut(key);
        set_token_config(
            cfg,
            whitelisted,
            is_native,
            min_limit,
            max_limit,
            treasury_id,
            is_mint_burn,
            is_locked,
        );

        return
    };

    let cfg = create_token_config(
        whitelisted,
        is_native,
        is_mint_burn,
        min_limit,
        max_limit,
        treasury_id,
        is_locked,
    );
    config.add(key, cfg);
}

public(package) fun set_token_config(
    config: &mut TokenConfig,
    whitelisted: bool,
    is_native: bool,
    min_limit: u64,
    max_limit: u64,
    treasury_id: Option<ID>,
    is_mint_burn: bool,
    is_locked: bool,
) {
    set_token_config_whitelisted(config, whitelisted);
    set_token_config_is_native(config, is_native);
    set_token_config_is_mint_burn(config, is_mint_burn);
    set_token_config_min_limit(config, min_limit);
    set_token_config_max_limit(config, max_limit);
    config.treasury_id = treasury_id;
    set_token_config_is_locked(config, is_locked);
}

public fun create_token_config(
    whitelisted: bool,
    is_native: bool,
    is_mint_burn: bool,
    min_limit: u64,
    max_limit: u64,
    treasury_id: Option<ID>,
    is_locked: bool,
): TokenConfig {
    TokenConfig {
        whitelisted,
        is_native,
        is_mint_burn,
        min_limit,
        max_limit,
        total_balance: 0,
        treasury_id,
        is_locked,
    }
}
