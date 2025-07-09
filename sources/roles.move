module bridge_safe::roles;

public struct AdminCap has key, store {
    id: UID,
}

public struct BridgeCap has key, store {
    id: UID,
}

public fun publish_caps(ctx: &mut TxContext): (AdminCap, BridgeCap) {
    (AdminCap { id: object::new(ctx) }, BridgeCap { id: object::new(ctx) })
}

public entry fun transfer_admin_capability(
    _current_admin_cap: &AdminCap,
    admin_cap: AdminCap,
    new_admin: address,
) {
    assert!(new_admin != @0x0, 0);
    transfer::public_transfer(admin_cap, new_admin);
}

public entry fun transfer_bridge_capability(
    _admin_cap: &AdminCap,
    bridge_cap: BridgeCap,
    new_bridge: address,
) {
    assert!(new_bridge != @0x0, 0);
    transfer::public_transfer(bridge_cap, new_bridge);
}
