module safe_module::safe_module {
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::table::{Self, Table};
    use shared_structs::shared_structs::{Self, Batch, Deposit, DepositStatus};
    use token_module::token_module::{Self, Token};

    public struct Safe has key {
        id: UID,
        whitelisted_tokens: Table<address, bool>,
        batches: Table<u64, Batch>,
        batch_deposits: Table<u64, vector<Deposit>>,
        batches_count: u64,
        deposits_count: u64,
        batch_size: u16,
        admin: address,
        paused: bool,
    }

    public fun whitelist_token(
        safe: &mut Safe,
        token: address,
        sender: address
    ) {
        assert!(safe.admin == sender, 0x2);
        table::add(&mut safe.whitelisted_tokens, token, true);
    }

    public fun deposit(
        safe: &mut Safe,
        token: &Token,
        amount: u64,
        recipient: vector<u8>,
        sender: address,
        ctx: &mut TxContext
    ) {
        assert!(!safe.paused, 0x3);
        let token_addr = token_module::get_token_address(token);
        assert!(table::contains(&safe.whitelisted_tokens, token_addr), 0x4);

        token_module::transfer(token, sender, object::id(&safe.id), amount);

        let mut batch_nonce = safe.batches_count;
        let mut batch: Batch;
        if (batch_nonce == 0 || _should_create_new_batch(safe, batch_nonce)) {
            batch_nonce = batch_nonce + 1;
            safe.batches_count = batch_nonce;
            batch = Batch {
                nonce: batch_nonce,
                block_number: ctx.block(),
                last_updated_block_number: ctx.block(),
                deposits_count: 0,
            };
            table::insert(&mut safe.batches, batch_nonce, batch);
            table::insert(&mut safe.batch_deposits, batch_nonce, vector::empty());
        } else {
            batch = table::borrow_mut(&mut safe.batches, &batch_nonce).unwrap();
        }

        let deposit_nonce = safe.deposits_count + 1;
        safe.deposits_count = deposit_nonce;

        let deposit = Deposit {
            nonce: deposit_nonce,
            token_address: token_addr,
            amount,
            depositor: sender,
            recipient,
            status: DepositStatus::Pending,
        };

        let deposits = table::borrow_mut(&mut safe.batch_deposits, &batch_nonce).unwrap();
        vector::push_back(deposits, deposit);

        batch.deposits_count = batch.deposits_count + 1;
        batch.last_updated_block_number = ctx.block();
        table::insert(&mut safe.batches, batch_nonce, batch);
    }

    fun _should_create_new_batch(safe: &Safe, batch_nonce: u64): bool {
        if (batch_nonce == 0) {
            true
        } else {
            let batch = table::borrow(&safe.batches, &batch_nonce).unwrap();
            batch.deposits_count >= safe.batch_size
        }
    }

     public fun transfer(
        safe: &mut Safe,
        token: &mut token_module::Token,
        amount: u64,
        recipient: address,
        sender: address
    ) {
        assert!(safe.admin == sender, 0x2);
        token_module::transfer(token, object::id(&safe.id), recipient, amount);
    }

    public fun pause(safe: &mut Safe, sender: address) {
        assert!(safe.admin == sender, 0x10); 
        safe.paused = true;
    }

    public fun unpause(safe: &mut Safe, sender: address) {
        assert!(safe.admin == sender, 0x11); 
        safe.paused = false;
    }
}