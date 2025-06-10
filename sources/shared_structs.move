module 0x1::shared_structs {

    public enum DepositStatus has copy, drop, store {
        None,
        Pending,
        InProgress,
        Executed,
        Rejected
    }

    public struct Deposit has copy, drop, store {
        nonce: u64,
        token_address: address,
        amount: u64,
        depositor: address,
        recipient: vector<u8>, 
        status: DepositStatus,
    }

    public struct CrossTransferStatus has copy, drop, store {
        statuses: vector<DepositStatus>,
        created_block_number: u64,
    }

    public struct Batch has copy, drop, store {
        nonce: u64,
        block_number: u64,
        last_updated_block_number: u64,
        deposits_count: u16,
    }

    public struct DepositSCExtension has copy, drop, store {
        deposit_data: vector<u8>,
    }
}