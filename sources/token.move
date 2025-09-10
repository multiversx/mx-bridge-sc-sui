module token::bridge_token;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::token::{Self, TokenPolicy, Token};
use token::transfer_rule::{Self, TransferRule};

public struct BRIDGE_TOKEN has drop {}

fun init(witness: BRIDGE_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<BRIDGE_TOKEN>(
        witness,
        2,
        b"RRS",
        b"RRS",
        b"",
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
    policy.share_policy();
    transfer::public_transfer(policy_cap, ctx.sender());
    transfer::public_transfer(treasury_cap, ctx.sender())
}

public fun mint_public_transfer(
    treasury_cap: &mut TreasuryCap<BRIDGE_TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = treasury_cap.mint(amount, ctx);
    let (token, mut req) = token::from_coin(coin, ctx);
    token::confirm_with_treasury_cap(treasury_cap, req, ctx);
    let mut req = token::transfer(token, recipient, ctx);
    transfer_rule::verify(&mut req, ctx);
    token::confirm_with_treasury_cap(treasury_cap, req, ctx);
}

public fun policy_transfer(
    policy: &TokenPolicy<BRIDGE_TOKEN>,
    token: Token<BRIDGE_TOKEN>,
    recipient: address,
    ctx: &mut TxContext,
) {
    let mut req = token::transfer(token, recipient, ctx);

    transfer_rule::verify(&mut req, ctx);

    token::confirm_request(policy, req, ctx);
}
