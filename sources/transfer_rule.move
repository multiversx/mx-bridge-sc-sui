module token::transfer_rule;

use sui::token::{Self, TokenPolicy, ActionRequest};

const ETransferActionNotAllowed: u64 = 0;

public struct TransferRule has drop {}

const STAKE_CONTRACT: address = @0x69850e056619e84ade85fcade0228c1c6e35f1d94c5ef1d3190bc3b30ee7c594;
const SAFE_CONTRACT: address = @0xeb298a01aef58dce189dbb7d5aa53ea934a14067568ade05b152ab5a8be7df4e;

public fun verify<T>(request: &mut ActionRequest<T>, ctx: &mut TxContext) {
    let recipient_opt = request.recipient();
    if (!option::is_some(&recipient_opt)) {
        abort ETransferActionNotAllowed
    };

    let recipient_addr = option::borrow(&recipient_opt);
    let sender_addr = request.sender();

    if (*recipient_addr == STAKE_CONTRACT || sender_addr == SAFE_CONTRACT) {
        token::add_approval(TransferRule {}, request, ctx);
        return
    };

    abort ETransferActionNotAllowed
}
