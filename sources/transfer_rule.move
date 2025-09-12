module token::transfer_rule;

use sui::token::{Self as token, ActionRequest, TokenPolicy, TokenPolicyCap};

const ETransferActionNotAllowed: u64 = 0;
const ERecipientNotSet: u64 = 1;
const ENotConfigured: u64 = 2;

public struct TransferRule has drop {}

public struct TransferRuleConfig has store {
    stake_address: option::Option<address>,
}

public fun verify<T>(request: &mut ActionRequest<T>, policy: &TokenPolicy<T>, ctx: &mut TxContext) {
    let recipient_opt = request.recipient();
    if (!option::is_some(&recipient_opt)) {
        abort ERecipientNotSet
    };
    let to = *option::borrow(&recipient_opt);

    let cfg = token::rule_config<_, TransferRule, TransferRuleConfig>(TransferRule {}, policy);
    if (!option::is_some(&cfg.stake_address)) {
        abort ENotConfigured
    };
    let stake = *option::borrow(&cfg.stake_address);

    if (to != stake) {
        abort ETransferActionNotAllowed
    };

    token::add_approval(TransferRule {}, request, ctx);
}

public fun init_config<T>(
    policy: &mut TokenPolicy<T>,
    cap: &TokenPolicyCap<T>,
    stake: address,
    ctx: &mut TxContext,
) {
    let cfg = TransferRuleConfig { stake_address: option::some(stake) };
    let rule = TransferRule {};
    token::add_rule_config<_, TransferRule, TransferRuleConfig>(rule, policy, cap, cfg, ctx)
}

public fun set_stake_address<T>(
    policy: &mut TokenPolicy<T>,
    cap: &TokenPolicyCap<T>,
    stake: address,
) {
    let cfg = token::rule_config_mut<_, TransferRule, TransferRuleConfig>(
        TransferRule {},
        policy,
        cap,
    );
    cfg.stake_address = option::some(stake)
}

public fun clear_stake_address<T>(policy: &mut TokenPolicy<T>, cap: &TokenPolicyCap<T>) {
    let cfg = token::rule_config_mut<_, TransferRule, TransferRuleConfig>(
        TransferRule {},
        policy,
        cap,
    );
    cfg.stake_address = option::none<address>()
}
