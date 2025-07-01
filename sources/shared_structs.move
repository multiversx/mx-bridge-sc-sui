module shared_structs::shared_structs;

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
    recipient: address,
}

public struct CrossTransferStatus has copy, drop, store {
    statuses: vector<DepositStatus>,
    created_block_number: u64,
}

public struct Batch has copy, drop, store {
    nonce: u64,
    block_number: u64,
    last_updated_block: u64,
    deposits_count: u16,
}

public struct TokenConfig has copy, drop, store {
    whitelisted: bool,
    is_native: bool,
    min_limit: u64,
    max_limit: u64,
    total_balance: u64,
}

public struct AdminRole has key {
    id: UID,
}

public fun create_deposit(
    nonce: u64,
    token_key: vector<u8>,
    amount: u64,
    sender: address,
    recipient: address,
): Deposit {
    Deposit {
        nonce,
        token_key,
        amount,
        sender,
        recipient,
    }
}

public fun create_batch(nonce: u64, block_number: u64): Batch {
    Batch {
        nonce,
        block_number,
        last_updated_block: block_number,
        deposits_count: 0,
    }
}

public fun create_cross_transfer_status(
    statuses: vector<DepositStatus>,
    created_block_number: u64,
): CrossTransferStatus {
    CrossTransferStatus {
        statuses,
        created_block_number,
    }
}

public fun cross_transfer_status_statuses(status: &CrossTransferStatus): vector<DepositStatus> {
    status.statuses
}

public fun cross_transfer_status_created_block_number(status: &CrossTransferStatus): u64 {
    status.created_block_number
}

public fun deposit_status_none(): DepositStatus {
    DepositStatus::None
}

public fun deposit_status_pending(): DepositStatus {
    DepositStatus::Pending
}

public fun deposit_status_in_progress(): DepositStatus {
    DepositStatus::InProgress
}

public fun deposit_status_executed(): DepositStatus {
    DepositStatus::Executed
}

public fun deposit_status_rejected(): DepositStatus {
    DepositStatus::Rejected
}

public fun update_batch_last_updated(batch: &mut Batch, block_number: u64) {
    batch.last_updated_block = block_number;
}

public fun increment_batch_deposits(batch: &mut Batch) {
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

public fun set_token_config_whitelisted(config: &mut TokenConfig, whitelisted: bool) {
    config.whitelisted = whitelisted;
}

public fun set_token_config_min_limit(config: &mut TokenConfig, min_limit: u64) {
    config.min_limit = min_limit;
}

public fun set_token_config_max_limit(config: &mut TokenConfig, max_limit: u64) {
    config.max_limit = max_limit;
}

public fun add_to_token_config_total_balance(config: &mut TokenConfig, amount: u64) {
    config.total_balance = config.total_balance + amount;
}

public fun subtract_from_token_config_total_balance(config: &mut TokenConfig, amount: u64) {
    config.total_balance = config.total_balance - amount;
}

public fun token_config_is_native(config: &TokenConfig): bool {
    config.is_native
}

public fun batch_nonce(batch: &Batch): u64 {
    batch.nonce
}

public fun batch_deposits_count(batch: &Batch): u16 {
    batch.deposits_count
}

public fun batch_last_updated_block(batch: &Batch): u64 {
    batch.last_updated_block
}

public fun batch_block_number(batch: &Batch): u64 {
    batch.block_number
}

public fun set_batch_deposits_count(batch: &mut Batch, count: u16) {
    batch.deposits_count = count;
}

public fun set_batch_last_updated_block(batch: &mut Batch, block: u64) {
    batch.last_updated_block = block;
}

public fun create_token_config(
    whitelisted: bool,
    is_native: bool,
    min_limit: u64,
    max_limit: u64,
): TokenConfig {
    TokenConfig {
        whitelisted,
        is_native,
        min_limit,
        max_limit,
        total_balance: 0,
    }
}
