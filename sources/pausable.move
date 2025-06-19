module bridge_safe::pausable;

use bridge_safe::events;

public struct Pause has copy, drop, store {
    paused: bool,
}

public fun new(): Pause {
    Pause { paused: false }
}

public fun pause(p: &mut Pause) {
    p.paused = true;
    events::emit_pause(true);
}

public fun unpause(p: &mut Pause) {
    p.paused = false;
    events::emit_pause(false);
}

public fun assert_not_paused(p: &Pause) {
    assert!(!p.paused, 0);
}

public fun assert_paused(p: &Pause) {
    assert!(p.paused, 0);
}
