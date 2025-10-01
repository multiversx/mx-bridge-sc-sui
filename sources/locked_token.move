module locked_token::bridge_token;

use sui::coin;
use sui::token;
use locked_token::treasury;


public struct BRIDGE_TOKEN has drop {}

#[allow(lint(share_owned))]
fun init(witness: BRIDGE_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<BRIDGE_TOKEN>(
        witness,
        6,
        b"TKN",
        b"TKN",
        b"Our bridge token",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);

    let (policy, policy_cap) = token::new_policy<BRIDGE_TOKEN>(
        &treasury_cap,
        ctx,
    );

    let t = treasury::new(
        treasury_cap, 
        policy_cap,
        ctx.sender(),
        ctx
    );

    policy.share_policy();
    transfer::public_share_object(t);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(BRIDGE_TOKEN {}, ctx)  // calls the real init that does create_currency, policy, etc.
}
