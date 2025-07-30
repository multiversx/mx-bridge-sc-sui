module bridge_safe::events;

use sui::event;

public struct DepositEvent has copy, drop {
    batch_id: u64,
    deposit_nonce: u64,
    sender: address,
    recipient: vector<u8>,
    amount: u64,
    token_type: vector<u8>,
}

public struct AdminRoleTransferred has copy, drop {
    previous_admin: address,
    new_admin: address,
}

public struct BridgeTransferred has copy, drop {
    previous_bridge: address,
    new_bridge: address,
}

public struct RelayerAdded has copy, drop {
    account: address,
    sender: address,
}

public struct RelayerRemoved has copy, drop {
    account: address,
    sender: address,
}

public struct Pause has copy, drop {
    is_pause: bool,
}

public struct TokenWhitelisted has copy, drop {
    token_type: vector<u8>,
    min_limit: u64,
    max_limit: u64,
    is_native: bool,
    is_mint_burn: bool,
}

public struct TokenRemovedFromWhitelist has copy, drop {
    token_type: vector<u8>,
}

public struct TokenLimitsUpdated has copy, drop {
    token_type: vector<u8>,
    new_min_limit: u64,
    new_max_limit: u64,
}

public struct BatchCreated has copy, drop {
    batch_nonce: u64,
    block_number: u64,
}

public struct TransferExecuted has copy, drop {
    recipient: address,
    amount: u64,
    token_type: vector<u8>,
    success: bool,
}

public struct BatchSettingsUpdated has copy, drop {
    batch_size: u16,
    batch_block_limit: u8,
    batch_settle_limit: u8,
}

public fun emit_deposit(
    batch_id: u64,
    deposit_nonce: u64,
    sender: address,
    recipient: vector<u8>,
    amount: u64,
    token_type: vector<u8>,
) {
    event::emit(DepositEvent {
        batch_id,
        deposit_nonce,
        sender,
        recipient,
        amount,
        token_type,
    });
}

public fun emit_admin_role_transferred(previous_admin: address, new_admin: address) {
    event::emit(AdminRoleTransferred { previous_admin, new_admin });
}

public fun emit_bridge_transferred(previous_bridge: address, new_bridge: address) {
    event::emit(BridgeTransferred { previous_bridge, new_bridge });
}

public fun emit_relayer_added(account: address, sender: address) {
    event::emit(RelayerAdded { account, sender });
}

public fun emit_relayer_removed(account: address, sender: address) {
    event::emit(RelayerRemoved { account, sender });
}

public fun emit_pause(is_pause: bool) {
    event::emit(Pause { is_pause });
}

public fun emit_token_whitelisted(
    token_type: vector<u8>,
    min_limit: u64,
    max_limit: u64,
    is_native: bool,
    is_mint_burn: bool,
) {
    event::emit(TokenWhitelisted {
        token_type,
        min_limit,
        max_limit,
        is_native,
        is_mint_burn,
    });
}

public fun emit_token_removed_from_whitelist(token_type: vector<u8>) {
    event::emit(TokenRemovedFromWhitelist { token_type });
}

public fun emit_token_limits_updated(
    token_type: vector<u8>,
    new_min_limit: u64,
    new_max_limit: u64,
) {
    event::emit(TokenLimitsUpdated {
        token_type,
        new_min_limit,
        new_max_limit,
    });
}

public fun emit_batch_created(batch_nonce: u64, block_number: u64) {
    event::emit(BatchCreated { batch_nonce, block_number });
}

public fun emit_transfer_executed(
    recipient: address,
    amount: u64,
    token_type: vector<u8>,
    success: bool,
) {
    event::emit(TransferExecuted {
        recipient,
        amount,
        token_type,
        success,
    });
}

public fun emit_batch_settings_updated(
    batch_size: u16,
    batch_block_limit: u8,
    batch_settle_limit: u8,
) {
    event::emit(BatchSettingsUpdated {
        batch_size,
        batch_block_limit,
        batch_settle_limit,
    });
}
