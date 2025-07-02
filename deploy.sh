#!/bin/bash

# Sui Bridge Smart Contracts Deployment Script

set -e  # Exit on any error

# Colors for output
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

# Addresses (will be filled during execution)
DEPLOYER_ADDRESS=""
BRIDGE_ADDRESS=""
RELAYER_ADDRESS=""
PACKAGE_ID=""
BRIDGE_SAFE_OBJECT=""
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
    
    print_info "Deployer Address: $DEPLOYER_ADDRESS"
    print_info "Bridge Address: $BRIDGE_ADDRESS" 
    print_info "Relayer Address: $RELAYER_ADDRESS"
}

# Deploy the smart contracts
deploy_contracts() {
    print_info "Deploying smart contracts..."
    print_warning "Note: Dependency verification is enabled for security"
    
    # Deploy the package with dependency verification
    DEPLOY_OUTPUT=$(sui client publish --gas-budget $GAS_BUDGET --verify-deps --json 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        print_warning "Deploy with --verify-deps failed, retrying without verification..."
        DEPLOY_OUTPUT=$(sui client publish --gas-budget $GAS_BUDGET --json 2>/dev/null)
        
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
  "admin_cap": "$ADMIN_CAP",
  "bridge_cap": "$BRIDGE_CAP",
  "relayer_cap": "$RELAYER_CAP",
  "deployer_address": "$DEPLOYER_ADDRESS",
  "bridge_address": "$BRIDGE_ADDRESS",
  "relayer_address": "$RELAYER_ADDRESS",
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
    echo ""
    echo -e "${YELLOW}Important addresses:${NC}"
    echo "Package ID: $PACKAGE_ID"
    echo "BridgeSafe Object: $BRIDGE_SAFE_OBJECT"
    echo "Admin Capability: $ADMIN_CAP"
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
    test_deposit
    save_deployment_info
    print_usage_instructions
}

# Run the script
main "$@"
