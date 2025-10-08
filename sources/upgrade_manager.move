/// Upgrade Manager - Coordinated System Upgrades
/// 
/// This module manages coordinated upgrades across both Bridge and BridgeSafe objects,
/// ensuring version compatibility and providing a unified upgrade interface.

module bridge_safe::upgrade_manager;

use bridge_safe::bridge::{Self, Bridge};
use bridge_safe::safe::{Self, BridgeSafe};
use bridge_safe::bridge_version_control;
use sui::event;

// === Events ===

public struct SystemUpgradeInitiated has copy, drop {
    safe_versions: vector<u64>,
    bridge_versions: vector<u64>,
    initiator: address,
}

public struct SystemUpgradeCompleted has copy, drop {
    new_version: u64,
    previous_versions: vector<u64>,
}

/// Start coordinated migration across both Safe and Bridge
public fun start_system_migration(
    safe: &mut BridgeSafe,
    bridge: &mut Bridge,
    ctx: &mut TxContext,
) {
    // Verify ownership through safe
    safe::checkOwnerRole(safe, ctx);
    
    // Start migration for both components
    safe::start_migration(safe, ctx);
    bridge::start_bridge_migration(bridge, safe, ctx);
    
    event::emit(SystemUpgradeInitiated {
        safe_versions: safe::compatible_versions(safe),
        bridge_versions: bridge::bridge_compatible_versions(bridge),
        initiator: ctx.sender(),
    });
}

/// Complete coordinated migration across both components
public fun complete_system_migration(
    safe: &mut BridgeSafe,
    bridge: &mut Bridge,
    ctx: &mut TxContext,
) {
    safe::checkOwnerRole(safe, ctx);
    
    // Complete migration for both components
    safe::complete_migration(safe, ctx);
    bridge::complete_bridge_migration(bridge, safe, ctx);
    
    event::emit(SystemUpgradeCompleted {
        new_version: bridge_version_control::current_version(),
        previous_versions: vector[bridge_version_control::current_version() - 1], // Previous version
    });
}

/// Abort coordinated migration if needed
public fun abort_system_migration(
    safe: &mut BridgeSafe,
    bridge: &mut Bridge,
    ctx: &mut TxContext,
) {
    safe::checkOwnerRole(safe, ctx);
    
    // Abort migration for both components
    safe::abort_migration(safe, ctx);
    bridge::abort_bridge_migration(bridge, safe, ctx);
}

/// Check if system-wide migration is in progress
public fun is_system_migration_in_progress(safe: &BridgeSafe, bridge: &Bridge): bool {
    safe::is_migration_in_progress(safe) || bridge::is_bridge_migration_in_progress(bridge)
}
