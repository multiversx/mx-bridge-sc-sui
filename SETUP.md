## Setup Process

#### 1. Package Publication

```bash
# Publish the smart contract package
sui client publish --gas-budget 100000000
```

#### 2. Bridge Initialization

```bash
# Initialize the bridge module with relayers and quorum
sui client call \
  --package <PACKAGE_ID> \
  --module bridge \
  --function initialize \
  --args \
    <RELAYER_ADDRESSES> \
    <RELAYER_PUBLIC_KEYS> \
    <INITIAL_QUORUM> \
    <SAFE_OBJECT_ID> \
    <BRIDGE_CAP> \
  --gas-budget 10000000
```

#### 3. Bridge Address Configuration

```bash
# Set the bridge address in the safe module
sui client call \
  --package <PACKAGE_ID> \
  --module safe \
  --function set_bridge_addr \
  --args \
    <SAFE_OBJECT_ID> \
    <ADMIN_CAP> \
    <BRIDGE_OBJECT_ID> \
  --gas-budget 10000000
```

#### 4. Token Whitelisting

```bash
# Whitelist each supported token
sui client call \
  --package <PACKAGE_ID> \
  --module safe \
  --function whitelist_token \
  --type-args <TOKEN_TYPE> \
  --args \
    <SAFE_OBJECT_ID> \
    <ADMIN_CAP> \
    <MIN_AMOUNT> \
    <MAX_AMOUNT> \
    <IS_NATIVE> \
  --gas-budget 10000000
```

#### 5. Configuration Setup (Optional)

```bash
# Set batch size
sui client call \
  --package <PACKAGE_ID> \
  --module safe \
  --function set_batch_size \
  --args \
    <SAFE_OBJECT_ID> \
    <ADMIN_CAP> \
    <BATCH_SIZE> \
  --gas-budget 10000000

# Set batch timeout
sui client call \
  --package <PACKAGE_ID> \
  --module safe \
  --function set_batch_timeout_ms \
  --args \
    <SAFE_OBJECT_ID> \
    <ADMIN_CAP> \
    <TIMEOUT_MS> \
  --gas-budget 10000000

# Set batch settlement timeout
sui client call \
  --package <PACKAGE_ID> \
  --module safe \
  --function set_batch_settle_timeout_ms \
  --args \
    <SAFE_OBJECT_ID> \
    <ADMIN_CAP> \
    <SETTLE_TIMEOUT_MS> \
    <CLOCK_OBJECT_ID> \
  --gas-budget 10000000

# Set token limits
sui client call \
  --package <PACKAGE_ID> \
  --module safe \
  --function set_token_min_limit \
  --type-args <TOKEN_TYPE> \
  --args \
    <SAFE_OBJECT_ID> \
    <ADMIN_CAP> \
    <MIN_AMOUNT> \
  --gas-budget 10000000

sui client call \
  --package <PACKAGE_ID> \
  --module safe \
  --function set_token_max_limit \
  --type-args <TOKEN_TYPE> \
  --args \
    <SAFE_OBJECT_ID> \
    <ADMIN_CAP> \
    <MAX_AMOUNT> \
  --gas-budget 10000000
```

#### 6. Supply Initialization (For Native Tokens)

```bash
# Initialize supply for native tokens
sui client call \
  --package <PACKAGE_ID> \
  --module safe \
  --function init_supply \
  --type-args <TOKEN_TYPE> \
  --args \
    <ADMIN_CAP> \
    <SAFE_OBJECT_ID> \
    <COIN_OBJECT_ID> \
  --gas-budget 10000000
```

#### 7. Bridge Configuration

```bash
# Set bridge quorum
sui client call \
  --package <PACKAGE_ID> \
  --module bridge \
  --function set_quorum \
  --args \
    <BRIDGE_OBJECT_ID> \
    <ADMIN_CAP> \
    <QUORUM_SIZE> \
  --gas-budget 10000000

# Set bridge batch settlement timeout
sui client call \
  --package <PACKAGE_ID> \
  --module bridge \
  --function set_batch_settle_timeout_ms \
  --args \
    <BRIDGE_OBJECT_ID> \
    <ADMIN_CAP> \
    <SAFE_OBJECT_ID> \
    <SETTLE_TIMEOUT_MS> \
    <CLOCK_OBJECT_ID> \
  --gas-budget 10000000
```

#### 8. Verification

After completing all setup steps, verify the bridge is ready:

- Check that all tokens are whitelisted
- Verify batch configurations are set correctly
- Confirm bridge address is properly configured
- Test a small deposit to ensure the system is operational

**Note**: The bridge is now ready for use once all initialization steps are completed and verified.
