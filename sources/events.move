module bridge_safe::events;

use sui::event;

public struct DepositEvent has copy, drop {
    batch_id: u64,
    deposit_nonce: u64,
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

public fun emit_deposit(batch_id: u64, deposit_nonce: u64) {
    event::emit(DepositEvent { batch_id, deposit_nonce });
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
