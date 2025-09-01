# SUI BRIDGE SMART CONTRACTS

A comprehensive bridge solution enabling secure token transfers between MultiversX and Sui blockchains, built with Move smart contracts on Sui.

## Abstract

This project implements a secure cross-chain bridge that facilitates token transfers from MultiversX to Sui. The bridge operates through a batch-based system where relayers process transactions in groups, ensuring efficiency and security through quorum validation and cryptographic verification.

## Bridge Flows

### 1. MultiversX → Sui Transfer Flow

When a bridge is initiated from MultiversX to Sui, the following process occurs:

1. **Batch Processing**: Relayers process incoming transactions and group them into batches
2. **Execute Transfer Calls**: The `execute_transfer` endpoint from the bridge module is called for each batch
   - Each call processes a portion of one batch, sorted by token type
   - Multiple `execute_transfer` calls may be required for complete batch execution (one per token type)
3. **Batch Completion**: The last transaction from the Programmable Transaction Block (PTB) marks the end of the batch
4. **Batch Execution Marking**: The batch is marked as executed in the bridge module
5. **Safe Transfer**: The bridge module calls the `transfer` function from the safe module
6. **Final Transfer**: Tokens are transferred from safe storage to the recipient address with the amount specified in the batch

#### Security Features

- **Quorum Validation**: At the `execute_transfer` level, the system validates quorum by:
  - Collecting relayer signatures
  - Constructing message hash
  - Verifying signatures using Ed25519's `verify` function
- **Batch-based Processing**: Ensures atomic execution of related transfers
- **Multi-token Support**: Handles different token types within the same batch efficiently

### 2. Sui → MultiversX Transfer Flow

When a user initiates a bridge transfer from Sui to MultiversX, the following process occurs:

1. **User Deposit**: The user calls the `deposit` endpoint from the safe module
2. **Batch Processing**: The system automatically creates or adds to existing batches based on timing and capacity
3. **Relayer Processing**: Relayers monitor batches and process them on the MultiversX side when complete
4. **Batch Status Updates**: Relayers mark each batch status after processing

#### Deposit Endpoint Logic

The `deposit` function in the safe module performs the following operations:

- **Validation Checks**:
  - Ensures the bridge is not paused
  - Validates recipient address format (32 bytes)
  - Verifies token is whitelisted
  - Checks amount is within configured limits (min/max)
  - Prevents zero amount deposits

- **Batch Management**:
  - Creates new batch if needed based on timing
  - Adds deposit to current active batch
  - Increments batch deposit counters
  - Updates batch timestamps

- **Token Storage**:
  - Stores deposited coins in the contract's coin storage
  - Joins with existing coins of the same type
  - Updates total balance for the token configuration

- **Event Emission**:
  - Emits deposit event with batch nonce, deposit nonce, sender, recipient, amount, and token type
  - Enables off-chain monitoring and indexing

## Project Structure

```
mx-bridge-sc-sui/
├── sources/                          # Move smart contract source files
│   ├── bridge_module.move            # Main bridge logic and execute_transfer
│   ├── events.move                   # Event definitions for bridge operations
│   ├── pausable.move                 # Pausable functionality for emergency stops
│   ├── roles.move                    # Role-based access control
│   ├── safe.move                     # Safe storage and transfer operations
│   ├── shared_structs.move           # Shared data structures
│   └── utils.move                    # Utility functions and helpers
```

## Key Components

### Bridge Module (`bridge_module.move`)

The bridge module is the core orchestrator that handles cross-chain transfer execution and relayer management.

#### **Capabilities**

- **Cross-chain Transfer Execution**: Processes transfers from MultiversX to Sui
- **Relayer Management**: Manages the set of authorized relayers
- **Quorum Validation**: Ensures multiple relayer signatures for security
- **Batch Execution Tracking**: Monitors and tracks batch execution status

#### **Roles & Access Control**

- **Admin**: Can modify quorum, add/remove relayers, change timeouts, transfer admin role
- **Relayer**: Can execute transfers and validate batches
- **Public**: Can view bridge state, batch information, and execution status

#### **Key Endpoints**

- **`execute_transfer<T>`**: Main function for executing cross-chain transfers
  - Requires relayer authentication
  - Validates quorum signatures
  - Processes multiple transfers in a single call
  - Marks batch completion status
- **`add_relayer`**: Admin function to add new relayers with public keys
- **`remove_relayer`**: Admin function to remove relayers (maintains quorum)
- **`set_quorum`**: Admin function to adjust required signature count

#### **Views & Queries**

- **`get_batch`**: Retrieve batch information and finality status
- **`get_batch_deposits`**: Get all deposits for a specific batch
- **`was_batch_executed`**: Check if a batch has been processed
- **`get_statuses_after_execution`**: Get transfer execution results
- **`is_relayer`**: Verify if an address is an authorized relayer

#### **Security Features**

- **Ed25519 Signature Verification**: Cryptographic validation of relayer signatures
- **Quorum Enforcement**: Minimum 3 signatures required for any transfer
- **Message Hash Construction**: Secure message construction for signature verification
- **Duplicate Signature Prevention**: Ensures each relayer signs only once

### Safe Module (`safe.move`)

The safe module manages token storage, user deposits, and batch creation for outbound transfers.

#### **Capabilities**

- **Token Storage**: Secure storage of deposited tokens
- **Batch Management**: Automatic batch creation and management
- **Token Whitelisting**: Configurable token support with limits
- **Emergency Controls**: Pausable operations for security incidents

#### **Roles & Access Control**

- **Admin**: Can whitelist/remove tokens, set limits, adjust timeouts, manage bridge address
- **Bridge**: Can transfer tokens out (requires BridgeCap)
- **Public**: Can deposit tokens and view safe state
- **Pausable**: All operations can be paused by admin

#### **Key Endpoints**

- **`deposit<T>`**: User function to deposit tokens for cross-chain transfer
  - Validates token whitelist status
  - Checks amount limits (min/max)
  - Automatically manages batch creation
  - Emits deposit events

#### **Storage Mechanism - Bag of Coins**

The safe module uses a sophisticated storage system to manage deposited tokens efficiently:

- **Coin Storage**: Uses Sui's `Bag` data structure to store coins of different token types
- **Type-based Organization**: Each token type has its own storage slot identified by the token's type name bytes
- **Automatic Coin Joining**: When new deposits arrive, coins of the same type are automatically joined together
- **Efficient Management**: The system maintains a single coin object per token type, reducing storage overhead

**How It Works:**

1. **Initial Deposit**: First deposit of a token type creates a new storage slot in the bag
2. **Subsequent Deposits**: Additional deposits of the same token type are joined with existing coins
3. **Balance Tracking**: Total balance is tracked separately in the token configuration for quick access
4. **Transfer Optimization**: When transfers occur, coins are split from the stored amount without affecting other operations

- **`transfer<T>`**: Bridge function to send tokens to recipients
  - Requires BridgeCap authentication
  - Updates token balances
  - Returns success/failure status
- **`whitelist_token<T>`**: Admin function to enable new tokens
- **`init_supply<T>`**: Admin function to initialize native token supply

#### **Views & Queries**

- **`get_batch`**: Get batch information and finality status
- **`get_deposits`**: Retrieve all deposits for a specific batch
- **`get_stored_coin_balance<T>`**: Check current token balance in safe
- **`is_token_whitelisted<T>`**: Verify if a token is supported
- **`get_token_min_limit<T>` / `get_token_max_limit<T>`**: Get token transfer limits

#### **Batch Management**

- **Automatic Creation**: New batches created based on timeouts or size limits
- **Configurable Timeouts**: Adjustable batch progress and settlement timeouts
- **Size Limits**: Configurable maximum batch size (default: 10, max: 100)
- **Timestamp Tracking**: Monitors batch creation and update times

#### **Configuration Management**

- **Token Limits**: Per-token minimum and maximum transfer amounts
- **Batch Timeouts**: Configurable intervals for batch progress and settlement
- **Bridge Address**: Configurable bridge contract address
- **Pause Controls**: Emergency pause/unpause functionality

#### **Event System**

- **Deposit Events**: Emitted for each successful deposit
- **Token Events**: Whitelist additions/removals and limit updates
- **Batch Events**: Batch creation and management events
- **Admin Events**: Configuration changes and role transfers

## Development

### Prerequisites

- Sui CLI installed and configured
- Move development environment set up

### Testing

```bash
# Run all tests
sui move test

# Run tests with coverage
sui move test --coverage

# Run specific test file
sui move test --filter bridge_comprehensive_tests
```

###Setup

For detailed setup instructions, see [SETUP.md](./SETUP.md).
