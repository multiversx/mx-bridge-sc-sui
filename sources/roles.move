module bridge_safe::roles;

public struct AdminCap has key, store {
    id: UID,
}

public struct BridgeCap has key, store {
    id: UID,
}

public struct RelayerCap has key, store {
    id: UID,
}

public fun publish_caps(ctx: &mut TxContext): (AdminCap, BridgeCap, RelayerCap) {
    (
        AdminCap { id: object::new(ctx) },
        BridgeCap { id: object::new(ctx) },
        RelayerCap { id: object::new(ctx) },
    )
}

public entry fun transfer_admin_capability(
    _current_admin_cap: &AdminCap,
    admin_cap: AdminCap,
    new_admin: address,
) {
    transfer::public_transfer(admin_cap, new_admin);
}

public entry fun transfer_bridge_capability(
    _admin_cap: &AdminCap,
    bridge_cap: BridgeCap,
    new_bridge: address,
) {
    transfer::public_transfer(bridge_cap, new_bridge);
}

public entry fun transfer_relayer_capability(
    _admin_cap: &AdminCap,
    relayer_cap: RelayerCap,
    new_relayer: address,
) {
    transfer::public_transfer(relayer_cap, new_relayer);
}

public entry fun create_relayer_capability(
    _admin_cap: &AdminCap,
    new_relayer: address,
    ctx: &mut TxContext,
) {
    let relayer_cap = RelayerCap { id: object::new(ctx) };
    transfer::public_transfer(relayer_cap, new_relayer);
}
