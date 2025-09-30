#[test_only]
module shared_structs::shared_structs_tests;

use shared_structs::shared_structs;

const MAX_U64: u64 = 18446744073709551615;

#[test]
fun test_token_config_is_mint_burn() {
    let mut config = shared_structs::create_token_config(
        true,  
        false, 
        100,   
        1000,  
        false  
    );
    
    shared_structs::set_token_config_is_mint_burn(&mut config, true);
    assert!(shared_structs::token_config_is_mint_burn(&config) == true, 0);
    
    shared_structs::set_token_config_is_mint_burn(&mut config, false);
    assert!(shared_structs::token_config_is_mint_burn(&config) == false, 1);
}

#[test]
fun test_set_batch_deposits_count() {
    let mut batch = shared_structs::create_batch(1, 1000);
    
    assert!(shared_structs::batch_deposits_count(&batch) == 0, 0);
    
    shared_structs::set_batch_deposits_count(&mut batch, 5);
    assert!(shared_structs::batch_deposits_count(&batch) == 5, 1);
    
    shared_structs::set_batch_deposits_count(&mut batch, 65535);
    assert!(shared_structs::batch_deposits_count(&batch) == 65535, 2);
    
    shared_structs::set_batch_deposits_count(&mut batch, 0);
    assert!(shared_structs::batch_deposits_count(&batch) == 0, 3);
}

#[test]
fun test_subtract_from_token_config_total_balance() {
    let mut config = shared_structs::create_token_config(
        true,  
        false, 
        100,   
        1000,  
        false  
    );
    
    shared_structs::add_to_token_config_total_balance(&mut config, 500);
    assert!(shared_structs::token_config_total_balance(&config) == 500, 0);
    
    shared_structs::subtract_from_token_config_total_balance(&mut config, 200);
    assert!(shared_structs::token_config_total_balance(&config) == 300, 1);
    
    shared_structs::subtract_from_token_config_total_balance(&mut config, 300);
    assert!(shared_structs::token_config_total_balance(&config) == 0, 2);
}

#[test]
#[expected_failure(abort_code = shared_structs::EUnderflow)]
fun test_subtract_from_token_config_total_balance_underflow() {
    let mut config = shared_structs::create_token_config(
        true,    
        false,   
        100,     
        1000,    
        false    
    );
    
    shared_structs::subtract_from_token_config_total_balance(&mut config, 1);
}

#[test]
#[expected_failure(abort_code = shared_structs::EUnderflow)]
fun test_subtract_from_token_config_total_balance_insufficient_funds() {
    let mut config = shared_structs::create_token_config(
        true,    
        false,   
        100,     
        1000,    
        false    
    );
    
    shared_structs::add_to_token_config_total_balance(&mut config, 100);
    
    shared_structs::subtract_from_token_config_total_balance(&mut config, 101);
}

#[test]
fun test_add_to_token_config_total_balance() {
    let mut config = shared_structs::create_token_config(
        true,    
        false,   
        100,     
        1000,    
        false    
    );
    
    assert!(shared_structs::token_config_total_balance(&config) == 0, 0);
    
    shared_structs::add_to_token_config_total_balance(&mut config, 250);
    assert!(shared_structs::token_config_total_balance(&config) == 250, 1);
    
    shared_structs::add_to_token_config_total_balance(&mut config, 750);
    assert!(shared_structs::token_config_total_balance(&config) == 1000, 2);
}

#[test]
#[expected_failure(abort_code = shared_structs::EOverflow)]
fun test_add_to_token_config_total_balance_overflow() {
    let mut config = shared_structs::create_token_config(
        true,    
        false,   
        100,     
        1000,    
        false    
    );
    
    shared_structs::add_to_token_config_total_balance(&mut config, MAX_U64);
    
    shared_structs::add_to_token_config_total_balance(&mut config, 1);
}

#[test]
#[expected_failure(abort_code = shared_structs::EOverflow)]
fun test_add_to_token_config_total_balance_near_max_overflow() {
    let mut config = shared_structs::create_token_config(
        true,    
        false,   
        100,     
        1000,    
        false    
    );
    
    shared_structs::add_to_token_config_total_balance(&mut config, MAX_U64 - 5);
    
    shared_structs::add_to_token_config_total_balance(&mut config, 10);
}

#[test]
fun test_set_token_config_is_native() {
    let mut config = shared_structs::create_token_config(
        true,    
        false,   
        100,     
        1000,    
        false    
    );
      
    assert!(shared_structs::token_config_is_native(&config) == false, 0);
    
    shared_structs::set_token_config_is_native(&mut config, true);
    assert!(shared_structs::token_config_is_native(&config) == true, 1);
    
    shared_structs::set_token_config_is_native(&mut config, false);
    assert!(shared_structs::token_config_is_native(&config) == false, 2);
}

#[test]
fun test_set_token_config_is_locked() {
    let mut config = shared_structs::create_token_config(
        true,    
        false,   
        100,     
        1000,    
        false    
    );
    
      
    assert!(shared_structs::get_token_config_is_locked(&config) == false, 0);
    
      
    shared_structs::set_token_config_is_locked(&mut config, true);
    assert!(shared_structs::get_token_config_is_locked(&config) == true, 1);
    
    // Set back to false
    shared_structs::set_token_config_is_locked(&mut config, false);
    assert!(shared_structs::get_token_config_is_locked(&config) == false, 2);
}

#[test]
fun test_cross_transfer_status_statuses() {
    let statuses = vector[
        shared_structs::deposit_status_executed(),
        shared_structs::deposit_status_rejected()
    ];
    
    let cross_transfer_status = shared_structs::create_cross_transfer_status(
        statuses,
        1234567890
    );
    
    let retrieved_statuses = shared_structs::cross_transfer_status_statuses(&cross_transfer_status);
    assert!(retrieved_statuses.length() == 2, 0);
}

#[test]
fun test_cross_transfer_status_created_timestamp_ms() {
    let statuses = vector[shared_structs::deposit_status_executed()];
    let timestamp = 1234567890;
    
    let cross_transfer_status = shared_structs::create_cross_transfer_status(
        statuses,
        timestamp
    );
    
    let retrieved_timestamp = shared_structs::cross_transfer_status_created_timestamp_ms(&cross_transfer_status);
    assert!(retrieved_timestamp == timestamp, 0);
}

#[test]
fun test_deposit_status_executed() {
    let status = shared_structs::deposit_status_executed();
    let statuses = vector[status];
    assert!(statuses.length() == 1, 0);
}

#[test]
fun test_deposit_status_rejected() {
    let status = shared_structs::deposit_status_rejected();
    let statuses = vector[status];
    assert!(statuses.length() == 1, 0);
}

#[test]
fun test_update_batch_last_updated() {
    let mut batch = shared_structs::create_batch(1, 1000);
    
    assert!(shared_structs::batch_last_updated_timestamp_ms(&batch) == 1000, 0);
    
    let new_timestamp = 2000;
    shared_structs::update_batch_last_updated(&mut batch, new_timestamp);
    assert!(shared_structs::batch_last_updated_timestamp_ms(&batch) == new_timestamp, 1);
    
    let another_timestamp = 3000;
    shared_structs::update_batch_last_updated(&mut batch, another_timestamp);
    assert!(shared_structs::batch_last_updated_timestamp_ms(&batch) == another_timestamp, 2);
    
    assert!(shared_structs::batch_timestamp_ms(&batch) == 1000, 3);
}

#[test]
fun test_combined_operations() {
    let mut config = shared_structs::create_token_config(
        true,    
        false,   
        100,     
        1000,    
        false    
    );
    
    let mut batch = shared_structs::create_batch(42, 5000);
    
    shared_structs::set_token_config_is_native(&mut config, true);
    shared_structs::set_token_config_is_locked(&mut config, true);
    shared_structs::set_token_config_is_mint_burn(&mut config, true);
    shared_structs::add_to_token_config_total_balance(&mut config, 500);
    
    assert!(shared_structs::token_config_is_native(&config) == true, 0);
    assert!(shared_structs::get_token_config_is_locked(&config) == true, 1);
    assert!(shared_structs::token_config_is_mint_burn(&config) == true, 2);
    assert!(shared_structs::token_config_total_balance(&config) == 500, 3);
    
    shared_structs::set_batch_deposits_count(&mut batch, 10);
    shared_structs::update_batch_last_updated(&mut batch, 6000);
    
    assert!(shared_structs::batch_deposits_count(&batch) == 10, 4);
    assert!(shared_structs::batch_last_updated_timestamp_ms(&batch) == 6000, 5);
    assert!(shared_structs::batch_nonce(&batch) == 42, 6);
    assert!(shared_structs::batch_timestamp_ms(&batch) == 5000, 7);
    
    shared_structs::subtract_from_token_config_total_balance(&mut config, 200);
    assert!(shared_structs::token_config_total_balance(&config) == 300, 8);
    
    shared_structs::add_to_token_config_total_balance(&mut config, 100);
    assert!(shared_structs::token_config_total_balance(&config) == 400, 9);
}