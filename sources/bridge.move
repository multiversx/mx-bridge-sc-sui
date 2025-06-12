module bridge::bridge {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{UID};
    use sui::object as object;
    use 0x2::table::{Self as table, Table};

    use validator_set::validator_set::{ValidatorSet};
    use shared_structs::shared_structs::{Deposit, DepositStatus};
    use token_module::token_module as tmod;
    use token_module::token_module::{Token};

    struct Bridge has key {
        id: UID,
        owner: address,
        validator_set: address,  
        token: address,          
        fee_bps: u64,           
        nonce: u64,
        paused: bool,
        locked: Table<address, u64>, 
    }

    public entry fun init(
        vset: &ValidatorSet,
        token: &Token,
        fee_bps: u64,
        ctx: &mut TxContext,
    ) {
        let cfg = Bridge {
            id: UID::new(ctx),
            owner: TxContext::sender(ctx),
            validator_set: object::uid_to_address(&vset.id),
            token: object::uid_to_address(&token.id),
            fee_bps,
            nonce: 0,
            paused: false,
            locked: table::new<address, u64>(ctx),
        };
        transfer cfg to TxContext::sender(ctx);
    }

    public entry fun deposit(
        bridge: &mut Bridge,
        token: &mut Token,
        amount: u64,
        recipient: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(!bridge.paused, 0);
        assert!(object::uid_to_address(&token.id) == bridge.token, 1);

        let sender = TxContext::sender(ctx);
        tmod::transfer(token, sender, object::uid_to_address(&bridge.id), amount);

        if (table::contains(&bridge.locked, sender)) {
            let bal = table::borrow_mut(&mut bridge.locked, sender);
            *bal = *bal + amount;
        } else {
            table::add(&mut bridge.locked, sender, amount);
        }

        let dep = Deposit {
            nonce: bridge.nonce,
            token_address: bridge.token,
            amount: amount,
            depositor: sender,
            recipient,
            status: DepositStatus::Pending,
        };
        bridge.nonce = bridge.nonce + 1;
        transfer dep to object::uid_to_address(&bridge.id);
    }

    public entry fun transfer(
        bridge: &mut Bridge,
        vset: &ValidatorSet,
        token: &mut Token,
        depositor: address,
        amount: u64,
        remote_tx_hash: vector<u8>,
        sigs: vector<vector<u8>>,
        ctx: &mut TxContext,
    ) {
        assert!(!bridge.paused, 2);
        assert!(bridge.validator_set == object::uid_to_address(&vset.id), 3);
        assert!(object::uid_to_address(&token.id) == bridge.token, 4);

        validator_set::validator_set::assert_sig(vset, remote_tx_hash, sigs);

        assert!(table::contains(&bridge.locked, depositor), 5);
        let bal = table::borrow_mut(&mut bridge.locked, depositor);
        assert!(*bal >= amount, 6);
        *bal = *bal - amount;

        let recipient = TxContext::sender(ctx);
        tmod::transfer(token, object::uid_to_address(&bridge.id), recipient, amount);
    }

    public entry fun set_paused(
        bridge: &mut Bridge,
        paused: bool,
        ctx: &mut TxContext,
    ) {
        assert!(TxContext::sender(ctx) == bridge.owner, 7);
        bridge.paused = paused;
    }
}
