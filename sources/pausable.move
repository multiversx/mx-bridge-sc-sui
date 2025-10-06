/// Pausable Module - Emergency Stop Functionality
/// 
/// This module provides pausable functionality for emergency stops.

module bridge_safe::pausable;

use bridge_safe::events;

const EContractPaused: u64 = 0;
const EContractNotPaused: u64 = 1;

public struct Pause has copy, drop, store {
    paused: bool,
}

public fun new(): Pause {
    Pause { paused: false }
}

public fun pause(p: &mut Pause) {
    if (!p.paused) {
        p.paused = true;
        events::emit_pause(true);
    }
}

public fun unpause(p: &mut Pause) {
    if (p.paused) {
        p.paused = false;
        events::emit_pause(false);
    }
}

public fun assert_not_paused(p: &Pause) {
    assert!(!p.paused, EContractPaused);
}

public fun assert_paused(p: &Pause) {
    assert!(p.paused, EContractNotPaused);
}

public fun is_paused(p: &Pause): bool {
    p.paused
}
