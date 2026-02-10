#[test_only]
module bridge_safe::events_tests;

use bridge_safe::events;
use sui::test_scenario::{Self as ts};

const ADMIN: address = @0xa11ce;
const USER: address = @0xb0b;
const RELAYER: address = @0xc0de;
const NEW_ADMIN: address = @0xdea1;
const NEW_BRIDGE: address = @0xfeed;

#[test]
fun test_emit_deposit() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a deposit event
        events::emit_deposit_v1(
            123, // batch_id
            456, // deposit_nonce
            USER, // sender
            b"recipient_address_bytes", // recipient
            1000, // amount
            b"TEST_TOKEN" // token_type
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_admin_role_transferred() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting an admin role transferred event
        events::emit_admin_role_transferred(ADMIN, NEW_ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_bridge_transferred() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a bridge transferred event
        events::emit_bridge_transferred(@0x1234, NEW_BRIDGE);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_relayer_added() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a relayer added event
        events::emit_relayer_added(RELAYER, ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_relayer_removed() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a relayer removed event
        events::emit_relayer_removed(RELAYER, ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_pause_true() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a pause event with true
        events::emit_pause(true);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_pause_false() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a pause event with false
        events::emit_pause(false);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_whitelisted() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token whitelisted event
        events::emit_token_whitelisted(
            b"TEST_TOKEN", // token_type
            100, // min_limit
            10000, // max_limit
            true, // is_native
            false, // is_mint_burn
            true // is_locked
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_whitelisted_all_false() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token whitelisted event with all boolean flags false
        events::emit_token_whitelisted(
            b"ANOTHER_TOKEN", // token_type
            50, // min_limit
            5000, // max_limit
            false, // is_native
            false, // is_mint_burn
            false // is_locked
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_whitelisted_mint_burn() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token whitelisted event with mint_burn true
        events::emit_token_whitelisted(
            b"MINT_BURN_TOKEN", // token_type
            1, // min_limit
            1000000, // max_limit
            false, // is_native
            true, // is_mint_burn
            false // is_locked
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_removed_from_whitelist() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token removed from whitelist event
        events::emit_token_removed_from_whitelist(b"REMOVED_TOKEN");
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_limits_updated() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token limits updated event
        events::emit_token_limits_updated(
            b"UPDATED_TOKEN", // token_type
            200, // new_min_limit
            20000 // new_max_limit
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_is_native_updated() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token is native updated event - true
        events::emit_token_is_native_updated(b"NATIVE_TOKEN", true);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_is_native_updated_false() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token is native updated event - false
        events::emit_token_is_native_updated(b"NON_NATIVE_TOKEN", false);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_is_locked_updated() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token is locked updated event - true
        events::emit_token_is_locked_updated(b"LOCKED_TOKEN", true);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_is_locked_updated_false() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token is locked updated event - false
        events::emit_token_is_locked_updated(b"UNLOCKED_TOKEN", false);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_is_mint_burn_updated() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token is mint burn updated event - true
        events::emit_token_is_mint_burn_updated(b"MINT_BURN_TOKEN", true);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_token_is_mint_burn_updated_false() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a token is mint burn updated event - false
        events::emit_token_is_mint_burn_updated(b"REGULAR_TOKEN", false);
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_batch_created() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a batch created event
        events::emit_batch_created(
            789, // batch_nonce
            1000000 // block_number
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_transfer_executed_success() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a transfer executed event - success
        events::emit_transfer_executed(
            USER, // recipient
            5000, // amount
            b"TRANSFER_TOKEN", // token_type
            true // success
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_transfer_executed_failure() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a transfer executed event - failure
        events::emit_transfer_executed(
            USER, // recipient
            5000, // amount
            b"FAILED_TOKEN", // token_type
            false // success
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_batch_settings_updated() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a batch settings updated event
        events::emit_batch_settings_updated(
            100, // batch_size (u16)
            50, // batch_block_limit (u8)
            25 // batch_settle_limit (u8)
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_batch_settings_updated_max_values() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        events::emit_batch_settings_updated(
            65535, // batch_size (u16 max)
            255, // batch_block_limit (u8 max)
            255 // batch_settle_limit (u8 max)
        );
    };
    
    ts::end(scenario);
}


#[test]
fun test_emit_deposit_with_empty_vectors() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        // Test emitting a deposit event with empty vectors
        events::emit_deposit_v1(
            0, 
            0, 
            @0x0,
            vector::empty<u8>(), 
            0, 
            vector::empty<u8>() 
        );
    };
    
    ts::end(scenario);
}

#[test]
fun test_emit_deposit_with_large_values() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        events::emit_deposit_v1(
            18446744073709551615, 
            18446744073709551615, 
            @0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 
            b"very_long_recipient_address_that_could_potentially_be_quite_large", 
            18446744073709551615, 
            b"VERY_LONG_TOKEN_TYPE_NAME_FOR_TESTING_PURPOSES" 
        );
    };
    
    ts::end(scenario);
}

#[test(expected_failure(abort_code = EDeprecated))]
fun test_old_emit_deposit_aborts() {
    let mut scenario = ts::begin(ADMIN);

    scenario.next_tx(ADMIN);
    {
        events::emit_deposit(
            18446744073709551615,
            18446744073709551615,
            @0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
            b"very_long_recipient_address_that_could_potentially_be_quite_large",
            18446744073709551615,
            b"VERY_LONG_TOKEN_TYPE_NAME_FOR_TESTING_PURPOSES"
        );
    };

    ts::end(scenario);
}

#[test]
fun test_multiple_events_in_sequence() {
    let mut scenario = ts::begin(ADMIN);
    
    scenario.next_tx(ADMIN);
    {
        events::emit_admin_role_transferred(ADMIN, NEW_ADMIN);
        events::emit_pause(true);
        events::emit_relayer_added(RELAYER, ADMIN);
        events::emit_token_whitelisted(b"SEQ_TOKEN", 1, 1000, true, false, true);
        events::emit_batch_created(1, 100);
        events::emit_transfer_executed(USER, 500, b"SEQ_TOKEN", true);
        events::emit_pause(false);
    };
    
    ts::end(scenario);
}