#!/bin/bash

set -e  # Exit on any error

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NETWORK=${NETWORK:-"testnet"}  # Can be "testnet", "devnet", or "mainnet"
GAS_BUDGET=${GAS_BUDGET:-"100000000"}  # 0.1 SUI
BATCH_SIZE=${BATCH_SIZE:-"10"}
MIN_AMOUNT=${MIN_AMOUNT:-"1000"}      # Minimum deposit amount (1000 MIST = 0.000001 SUI)
MAX_AMOUNT=${MAX_AMOUNT:-"1000000000000"}  # Maximum deposit amount (1000 SUI)
DEBUG=${DEBUG:-"false"}  # Set to "true" for debug output

# Bridge Configuration
INITIAL_QUORUM=${INITIAL_QUORUM:-"3"}  # Minimum quorum for bridge operations
RELAYER1_ADDRESS=${RELAYER1_ADDRESS:-""}  # Will use deployer if not set
RELAYER2_ADDRESS=${RELAYER2_ADDRESS:-""}  # Will use deployer if not set  
RELAYER3_ADDRESS=${RELAYER3_ADDRESS:-""}  # Will use deployer if not set

# Test relayer public keys (32 bytes each) - FOR TESTING ONLY!
# In production, these should be real Ed25519 public keys from the relayers
RELAYER1_PUBKEY="0x12345678901234567890123456789012"
RELAYER2_PUBKEY="0xabcdefghijklmnopqrstuvwxyz123456"
RELAYER3_PUBKEY="0xABCDEFGHIJKLMNOPQRSTUVWXYZ123456"

# Addresses (will be filled during execution)
DEPLOYER_ADDRESS=""
BRIDGE_ADDRESS=""
RELAYER_ADDRESS=""
PACKAGE_ID=""
BRIDGE_SAFE_OBJECT=""
BRIDGE_OBJECT=""
ADMIN_CAP=""
BRIDGE_CAP=""
RELAYER_CAP=""

# Sui token type (native SUI)
SUI_TYPE="0x2::sui::SUI"

# USDC token type on Sui (this is an example - replace with actual USDC type when available)
USDC_TYPE="0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"

echo -e "${BLUE}🚀 Starting Sui Bridge Smart Contracts Deployment${NC}"
echo -e "${YELLOW}Network: $NETWORK${NC}"
echo -e "${YELLOW}Gas Budget: $GAS_BUDGET${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${BLUE}🔍 DEBUG: $1${NC}"
    fi
}

# Check if sui CLI is installed
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v sui &> /dev/null; then
        print_error "Sui CLI is not installed. Please install it first."
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first (brew install jq on macOS)."
    fi
    
    # Check if we're in the right directory
    if [ ! -f "Move.toml" ]; then
        print_error "Move.toml not found. Please run this script from the project root."
    fi
    
    # Check if project builds
    print_info "Building project to verify it compiles..."
    if ! sui move build 2>/dev/null; then
        print_error "Project failed to build. Please fix compilation errors first."
    fi
    
    print_status "Prerequisites check passed"
}

# Get current active address
get_addresses() {
    print_info "Getting deployer address..."
    DEPLOYER_ADDRESS=$(sui client active-address)
    
    # For this demo, we'll use the same address for bridge and relayer
    # In production, these should be different addresses
    BRIDGE_ADDRESS=${BRIDGE_ADDRESS:-$DEPLOYER_ADDRESS}
    RELAYER_ADDRESS=${RELAYER_ADDRESS:-$DEPLOYER_ADDRESS}
    
    # Set up relayer addresses - use deployer if not specified
    RELAYER1_ADDRESS=${RELAYER1_ADDRESS:-$DEPLOYER_ADDRESS}
    RELAYER2_ADDRESS=${RELAYER2_ADDRESS:-$DEPLOYER_ADDRESS}
    RELAYER3_ADDRESS=${RELAYER3_ADDRESS:-$DEPLOYER_ADDRESS}
    
    print_info "Deployer Address: $DEPLOYER_ADDRESS"
    print_info "Bridge Address: $BRIDGE_ADDRESS" 
    print_info "Relayer Address: $RELAYER_ADDRESS"
    print_info "Relayer 1 Address: $RELAYER1_ADDRESS"
    print_info "Relayer 2 Address: $RELAYER2_ADDRESS"
    print_info "Relayer 3 Address: $RELAYER3_ADDRESS"
    print_info "Initial Quorum: $INITIAL_QUORUM"
}

# Deploy the smart contracts
deploy_contracts() {
    print_info "Deploying smart contracts..."
    print_warning "Note: Dependency verification is enabled for security"
    
    # Deploy the package with dependency verification
    DEPLOY_OUTPUT=$(sui client publish --verify-deps --json 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        print_warning "Deploy with --verify-deps failed, retrying without verification..."
        DEPLOY_OUTPUT=$(sui client publish --json 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            print_error "Failed to deploy contracts"
        fi
    fi
    
    print_debug "Deployment output: $DEPLOY_OUTPUT"
    
    # Extract package ID from deployment output
    PACKAGE_ID=$(echo "$DEPLOY_OUTPUT" | jq -r '.objectChanges[] | select(.type == "published") | .packageId')
    
    if [ -z "$PACKAGE_ID" ] || [ "$PACKAGE_ID" = "null" ]; then
        print_error "Failed to extract package ID from deployment output"
    fi
    
    # Extract created objects (BridgeSafe, AdminCap, BridgeCap, RelayerCap)
    BRIDGE_SAFE_OBJECT=$(echo "$DEPLOY_OUTPUT" | jq -r '.objectChanges[] | select(.objectType | contains("BridgeSafe")) | .objectId')
    ADMIN_CAP=$(echo "$DEPLOY_OUTPUT" | jq -r '.objectChanges[] | select(.objectType | contains("AdminCap")) | .objectId')
    BRIDGE_CAP=$(echo "$DEPLOY_OUTPUT" | jq -r '.objectChanges[] | select(.objectType | contains("BridgeCap")) | .objectId')
    RELAYER_CAP=$(echo "$DEPLOY_OUTPUT" | jq -r '.objectChanges[] | select(.objectType | contains("RelayerCap")) | .objectId')
    
    # Verify all objects were created
    if [ -z "$BRIDGE_SAFE_OBJECT" ] || [ "$BRIDGE_SAFE_OBJECT" = "null" ]; then
        print_error "Failed to extract BridgeSafe object ID"
    fi
    
    if [ -z "$ADMIN_CAP" ] || [ "$ADMIN_CAP" = "null" ]; then
        print_error "Failed to extract AdminCap object ID"
    fi
    
    print_status "Contracts deployed successfully!"
    print_info "Package ID: $PACKAGE_ID"
    print_info "BridgeSafe Object: $BRIDGE_SAFE_OBJECT"
    print_info "Admin Capability: $ADMIN_CAP"
    print_info "Bridge Capability: $BRIDGE_CAP"
    print_info "Relayer Capability: $RELAYER_CAP"
}

# Initialize the bridge with custom addresses (if different from deployer)
initialize_bridge() {
    if [ "$BRIDGE_ADDRESS" != "$DEPLOYER_ADDRESS" ] || [ "$RELAYER_ADDRESS" != "$DEPLOYER_ADDRESS" ]; then
        print_info "Initializing bridge with custom bridge and relayer addresses..."
        
        sui client call \
            --package $PACKAGE_ID \
            --module safe \
            --function initialize \
            --args $BRIDGE_ADDRESS $RELAYER_ADDRESS \
            --gas-budget $GAS_BUDGET
            
        if [ $? -eq 0 ]; then
            print_status "Bridge initialized with custom addresses"
        else
            print_error "Failed to initialize bridge"
        fi
    else
        print_info "Using default initialization (deployer as admin, bridge, and relayer)"
    fi
}

# Whitelist SUI token
whitelist_sui() {
    print_info "Whitelisting SUI token..."
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function whitelist_token \
        --type-args $SUI_TYPE \
        --args $BRIDGE_SAFE_OBJECT $ADMIN_CAP $MIN_AMOUNT $MAX_AMOUNT true \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "SUI token whitelisted successfully"
    else
        print_error "Failed to whitelist SUI token"
    fi
}

# Whitelist USDC token (example)
whitelist_usdc() {
    print_warning "Attempting to whitelist USDC token (example type)..."
    print_warning "Note: This may fail if the USDC token type doesn't exist on this network"
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function whitelist_token \
        --type-args $USDC_TYPE \
        --args $BRIDGE_SAFE_OBJECT $ADMIN_CAP $MIN_AMOUNT $MAX_AMOUNT false \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "USDC token whitelisted successfully"
    else
        print_warning "Failed to whitelist USDC token (this is expected if USDC doesn't exist on this network)"
    fi
}

# Set batch size
configure_batch_size() {
    print_info "Setting batch size to $BATCH_SIZE..."
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function set_batch_size \
        --args $BRIDGE_SAFE_OBJECT $ADMIN_CAP $BATCH_SIZE \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "Batch size configured successfully"
    else
        print_error "Failed to configure batch size"
    fi
}

# Initialize the bridge module with relayers
initialize_bridge_module() {
    print_info "Initializing bridge module..."
    print_warning "Using test public keys - replace with real keys in production!"
    
    # Convert hex strings to proper format for Sui CLI
    # Remove 0x prefix and ensure exactly 32 bytes (64 hex chars)
    PK1=$(echo $RELAYER1_PUBKEY | sed 's/0x//' | head -c 64)
    PK2=$(echo $RELAYER2_PUBKEY | sed 's/0x//' | head -c 64)
    PK3=$(echo $RELAYER3_PUBKEY | sed 's/0x//' | head -c 64)
    
    # Pad with zeros if needed to make exactly 32 bytes
    PK1=$(printf "%-64s" "$PK1" | tr ' ' '0')
    PK2=$(printf "%-64s" "$PK2" | tr ' ' '0')
    PK3=$(printf "%-64s" "$PK3" | tr ' ' '0')
    
    print_debug "Relayer addresses: [$RELAYER1_ADDRESS, $RELAYER2_ADDRESS, $RELAYER3_ADDRESS]"
    print_debug "Public keys: [0x$PK1, 0x$PK2, 0x$PK3]"
    
    BRIDGE_INIT_OUTPUT=$(sui client call \
        --package $PACKAGE_ID \
        --module bridge \
        --function initialize \
        --args "[$RELAYER1_ADDRESS,$RELAYER2_ADDRESS,$RELAYER3_ADDRESS]" "[0x$PK1,0x$PK2,0x$PK3]" $INITIAL_QUORUM $BRIDGE_SAFE_OBJECT $BRIDGE_CAP \
        --gas-budget $GAS_BUDGET \
        --json)
    
    if [ $? -eq 0 ]; then
        print_status "Bridge module initialized successfully!"
        
        # Extract the Bridge object ID from the output
        BRIDGE_OBJECT=$(echo "$BRIDGE_INIT_OUTPUT" | jq -r '.objectChanges[] | select(.objectType | contains("Bridge")) | .objectId')
        
        if [ -n "$BRIDGE_OBJECT" ] && [ "$BRIDGE_OBJECT" != "null" ]; then
            print_info "Bridge Object ID: $BRIDGE_OBJECT"
        else
            print_warning "Could not extract Bridge object ID from output"
        fi
        
        print_debug "Bridge initialization output: $BRIDGE_INIT_OUTPUT"
    else
        print_error "Failed to initialize bridge module"
    fi
}

# Test deposit functionality
test_deposit() {
    print_info "Testing deposit functionality with SUI..."
    
    # Get some coins to deposit
    COINS=$(sui client gas --json | jq -r '.[0].gasCoinId')
    
    if [ "$COINS" = "null" ] || [ -z "$COINS" ]; then
        print_warning "No gas coins found for testing deposit"
        return
    fi
    
    # Split a small amount for testing (0.001 SUI = 1,000,000 MIST)
    TEST_AMOUNT="1000000"
    
    print_info "Splitting coin for test deposit..."
    SPLIT_OUTPUT=$(sui client call \
        --package 0x2 \
        --module coin \
        --function split \
        --type-args $SUI_TYPE \
        --args $COINS $TEST_AMOUNT \
        --gas-budget $GAS_BUDGET \
        --json)
    
    if [ $? -ne 0 ]; then
        print_warning "Failed to split coin for testing"
        return
    fi
    
    # Extract the new coin ID
    TEST_COIN=$(echo "$SPLIT_OUTPUT" | jq -r '.objectChanges[] | select(.type == "created") | .objectId')
    
    print_info "Making test deposit with coin: $TEST_COIN"
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function deposit \
        --type-args $SUI_TYPE \
        --args $BRIDGE_SAFE_OBJECT $TEST_COIN $DEPLOYER_ADDRESS \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "Test deposit completed successfully!"
    else
        print_warning "Test deposit failed"
    fi
}

# Save deployment info
save_deployment_info() {
    print_info "Saving deployment information..."
    
    cat > deployment_info.json << EOF
{
  "network": "$NETWORK",
  "package_id": "$PACKAGE_ID",
  "bridge_safe_object": "$BRIDGE_SAFE_OBJECT",
  "bridge_object": "$BRIDGE_OBJECT",
  "admin_cap": "$ADMIN_CAP",
  "bridge_cap": "$BRIDGE_CAP",
  "relayer_cap": "$RELAYER_CAP",
  "deployer_address": "$DEPLOYER_ADDRESS",
  "bridge_address": "$BRIDGE_ADDRESS",
  "relayer_address": "$RELAYER_ADDRESS",
  "relayer_addresses": {
    "relayer1": "$RELAYER1_ADDRESS",
    "relayer2": "$RELAYER2_ADDRESS", 
    "relayer3": "$RELAYER3_ADDRESS"
  },
  "bridge_config": {
    "initial_quorum": $INITIAL_QUORUM,
    "relayer_public_keys": {
      "relayer1": "$RELAYER1_PUBKEY",
      "relayer2": "$RELAYER2_PUBKEY",
      "relayer3": "$RELAYER3_PUBKEY"
    }
  },
  "whitelisted_tokens": {
    "SUI": "$SUI_TYPE"
  },
  "configuration": {
    "batch_size": $BATCH_SIZE,
    "min_amount": $MIN_AMOUNT,
    "max_amount": $MAX_AMOUNT
  }
}
EOF
    
    print_status "Deployment info saved to deployment_info.json"
}

# Print usage instructions
print_usage_instructions() {
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📝 Usage Instructions:${NC}"
    echo ""
    echo -e "${YELLOW}To make a deposit:${NC}"
    echo "sui client call \\"
    echo "  --package $PACKAGE_ID \\"
    echo "  --module safe \\"
    echo "  --function deposit \\"
    echo "  --type-args $SUI_TYPE \\"
    echo "  --args $BRIDGE_SAFE_OBJECT <COIN_OBJECT_ID> <RECIPIENT_ADDRESS> \\"
    echo "  --gas-budget $GAS_BUDGET"
    echo ""
    echo -e "${YELLOW}To check bridge status:${NC}"
    echo "sui client object $BRIDGE_SAFE_OBJECT"
    if [ -n "$BRIDGE_OBJECT" ] && [ "$BRIDGE_OBJECT" != "null" ]; then
        echo "sui client object $BRIDGE_OBJECT"
    fi
    echo ""
    echo -e "${YELLOW}Important addresses:${NC}"
    echo "Package ID: $PACKAGE_ID"
    echo "BridgeSafe Object: $BRIDGE_SAFE_OBJECT"
    if [ -n "$BRIDGE_OBJECT" ] && [ "$BRIDGE_OBJECT" != "null" ]; then
        echo "Bridge Object: $BRIDGE_OBJECT"
    fi
    echo "Admin Capability: $ADMIN_CAP"
    echo "Bridge Capability: $BRIDGE_CAP"
    echo ""
    echo -e "${YELLOW}Bridge Configuration:${NC}"
    echo "Initial Quorum: $INITIAL_QUORUM"
    echo "Relayers: $RELAYER1_ADDRESS, $RELAYER2_ADDRESS, $RELAYER3_ADDRESS"
    echo ""
    echo -e "${BLUE}All deployment details saved in deployment_info.json${NC}"
}

# Main execution
main() {
    check_prerequisites
    get_addresses
    deploy_contracts
    initialize_bridge
    whitelist_sui
    # whitelist_usdc  # Uncomment if you want to try whitelisting USDC
    configure_batch_size
    initialize_bridge_module
    test_deposit
    save_deployment_info
    print_usage_instructions
}

# Run the script
main "$@"
