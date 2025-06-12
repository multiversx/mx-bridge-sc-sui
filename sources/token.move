module token_module::token_module {
    use sui::object::{UID, new};
    use sui::tx_context::TxContext;
    use 0x2::table::{Self, Table};

    public struct Token has key {
        id: UID,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        total_supply: u64,
        balances: Table<address, u64>,
    }

    public fun get_token_address(token: &Token): address {
        object::uid_to_address(&token.id)
    }

    public fun create(
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        initial_supply: u64,
        owner: address,
        ctx: &mut TxContext
    ): Token {
        let mut balances = table::new<address, u64>(ctx);
        table::add(&mut balances, owner, initial_supply);
        Token {
            id: new(ctx),
            name,
            symbol,
            decimals,
            total_supply: initial_supply,
            balances,
        }
    }

    public fun transfer(
        token: &mut Token,
        from: address,
        to: address,
        amount: u64
    ) {
        assert!(table::contains(&token.balances, from), 0x1);
        let from_balance = table::borrow_mut(&mut token.balances, from);
        assert!(*from_balance >= amount, 0x2);
        *from_balance = *from_balance - amount;

        if (table::contains(&token.balances, to)) {
            let to_balance = table::borrow_mut(&mut token.balances, to);
            *to_balance = *to_balance + amount;
        } else {
            table::add(&mut token.balances, to, amount);
        }
    }

    public fun balance_of(token: &Token, owner: address): u64 {
        if (table::contains(&token.balances, owner)) {
            *table::borrow(&token.balances, owner)
        } else {
            0
        }
    }
}