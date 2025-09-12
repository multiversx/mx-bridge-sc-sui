module token::bridge_token;

use sui::coin::{Self, TreasuryCap};
use sui::token::{Self, TokenPolicy, Token, TokenPolicyCap};
use token::transfer_rule::{Self, TransferRule};

public struct BRIDGE_TOKEN has drop {}

fun init(witness: BRIDGE_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<BRIDGE_TOKEN>(
        witness,
        2,
        b"TKN",
        b"TKN",
        b"Our bridge token",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    let (mut policy, policy_cap) = token::new_policy<BRIDGE_TOKEN>(
        &treasury_cap,
        ctx,
    );
    token::add_rule_for_action<BRIDGE_TOKEN, TransferRule>(
        &mut policy,
        &policy_cap,
        token::transfer_action(),
        ctx,
    );
    transfer_rule::init_config<BRIDGE_TOKEN>(
        &mut policy,
        &policy_cap,
        tx_context::sender(ctx),
        ctx,
    );

    policy.share_policy();
    transfer::public_transfer(policy_cap, ctx.sender());
    transfer::public_transfer(treasury_cap, ctx.sender())
}

public fun mint_and_transfer(
    treasury_cap: &mut TreasuryCap<BRIDGE_TOKEN>,
    policy_cap: &mut TokenPolicyCap<BRIDGE_TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = treasury_cap.mint(amount, ctx);
    let (token, req) = token::from_coin(coin, ctx);
    token::confirm_with_treasury_cap(treasury_cap, req, ctx);

    let request = token::transfer(token, recipient, ctx);
    token::confirm_with_policy_cap(policy_cap, request, ctx);
}

public fun transfer_with_policy(
    policy: &TokenPolicy<BRIDGE_TOKEN>,
    token: Token<BRIDGE_TOKEN>,
    recipient: address,
    ctx: &mut TxContext,
) {
    let mut req = token::transfer(token, recipient, ctx);

    transfer_rule::verify(&mut req, policy, ctx);

    token::confirm_request(policy, req, ctx);
}

public fun set_stake(
    policy: &mut TokenPolicy<BRIDGE_TOKEN>,
    cap: &TokenPolicyCap<BRIDGE_TOKEN>,
    new_stake: address,
) {
    transfer_rule::set_stake_address<BRIDGE_TOKEN>(policy, cap, new_stake)
}
