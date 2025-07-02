#!/bin/bash

# Sui Bridge Helper Script
# Common operations for the deployed bridge

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if deployment info exists
if [ ! -f "deployment_info.json" ]; then
    echo -e "${RED}❌ deployment_info.json not found. Please run deploy.sh first.${NC}"
    exit 1
fi

# Load deployment info
PACKAGE_ID=$(jq -r '.package_id' deployment_info.json)
BRIDGE_SAFE_OBJECT=$(jq -r '.bridge_safe_object' deployment_info.json)
ADMIN_CAP=$(jq -r '.admin_cap' deployment_info.json)
BRIDGE_CAP=$(jq -r '.bridge_cap' deployment_info.json)
RELAYER_CAP=$(jq -r '.relayer_cap' deployment_info.json)
SUI_TYPE=$(jq -r '.whitelisted_tokens.SUI' deployment_info.json)
GAS_BUDGET="50000000"

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

show_help() {
    echo -e "${BLUE}Sui Bridge Helper Script${NC}"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  status                    - Show bridge status"
    echo "  deposit <amount> <recipient>  - Make a deposit (amount in MIST)"
    echo "  whitelist <token_type>    - Whitelist a new token"
    echo "  pause                     - Pause the bridge (admin only)"
    echo "  unpause                   - Unpause the bridge (admin only)"
    echo "  batch-size <size>         - Set batch size (admin only)"
    echo "  balance                   - Show your balance"
    echo "  help                      - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 deposit 1000000 0x123...  # Deposit 0.001 SUI"
    echo "  $0 status                     # Check bridge status"
    echo "  $0 balance                    # Check your balance"
}

show_status() {
    print_info "Fetching bridge status..."
    
    echo -e "${YELLOW}Bridge Safe Object:${NC}"
    sui client object $BRIDGE_SAFE_OBJECT
    
    echo ""
    echo -e "${YELLOW}Your Capabilities:${NC}"
    echo "Admin Cap: $ADMIN_CAP"
    echo "Bridge Cap: $BRIDGE_CAP" 
    echo "Relayer Cap: $RELAYER_CAP"
}

make_deposit() {
    local amount=$1
    local recipient=$2
    
    if [ -z "$amount" ] || [ -z "$recipient" ]; then
        print_error "Usage: $0 deposit <amount> <recipient>"
    fi
    
    print_info "Making deposit of $amount MIST to $recipient..."
    
    # Get a coin to split from
    COINS=$(sui client gas --json | jq -r '.[0].gasCoinId')
    
    if [ "$COINS" = "null" ] || [ -z "$COINS" ]; then
        print_error "No gas coins found"
    fi
    
    # Split the exact amount needed
    print_info "Splitting coin for deposit..."
    SPLIT_OUTPUT=$(sui client call \
        --package 0x2 \
        --module coin \
        --function split \
        --type-args $SUI_TYPE \
        --args $COINS $amount \
        --gas-budget $GAS_BUDGET \
        --json)
    
    if [ $? -ne 0 ]; then
        print_error "Failed to split coin"
    fi
    
    # Extract the new coin ID
    DEPOSIT_COIN=$(echo "$SPLIT_OUTPUT" | jq -r '.objectChanges[] | select(.type == "created") | .objectId')
    
    print_info "Making deposit with coin: $DEPOSIT_COIN"
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function deposit \
        --type-args $SUI_TYPE \
        --args $BRIDGE_SAFE_OBJECT $DEPOSIT_COIN $recipient \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "Deposit completed successfully!"
    else
        print_error "Deposit failed"
    fi
}

whitelist_token() {
    local token_type=$1
    
    if [ -z "$token_type" ]; then
        print_error "Usage: $0 whitelist <token_type>"
    fi
    
    print_info "Whitelisting token: $token_type"
    
    # Default limits
    local min_amount="1000"
    local max_amount="1000000000000"
    local is_native="false"
    
    # Check if it's SUI
    if [[ "$token_type" == *"sui::SUI"* ]]; then
        is_native="true"
    fi
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function whitelist_token \
        --type-args $token_type \
        --args $BRIDGE_SAFE_OBJECT $ADMIN_CAP $min_amount $max_amount $is_native \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "Token whitelisted successfully"
    else
        print_error "Failed to whitelist token"
    fi
}

pause_bridge() {
    print_info "Pausing bridge..."
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function pause \
        --args $BRIDGE_SAFE_OBJECT $ADMIN_CAP \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "Bridge paused successfully"
    else
        print_error "Failed to pause bridge"
    fi
}

unpause_bridge() {
    print_info "Unpausing bridge..."
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function unpause \
        --args $BRIDGE_SAFE_OBJECT $ADMIN_CAP \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "Bridge unpaused successfully"
    else
        print_error "Failed to unpause bridge"
    fi
}

set_batch_size() {
    local size=$1
    
    if [ -z "$size" ]; then
        print_error "Usage: $0 batch-size <size>"
    fi
    
    print_info "Setting batch size to $size..."
    
    sui client call \
        --package $PACKAGE_ID \
        --module safe \
        --function set_batch_size \
        --args $BRIDGE_SAFE_OBJECT $ADMIN_CAP $size \
        --gas-budget $GAS_BUDGET
    
    if [ $? -eq 0 ]; then
        print_status "Batch size set successfully"
    else
        print_error "Failed to set batch size"
    fi
}

show_balance() {
    print_info "Your SUI balance:"
    sui client balance
    
    print_info "Your objects:"
    sui client objects
}

# Main command handling
case "$1" in
    "status")
        show_status
        ;;
    "deposit")
        make_deposit "$2" "$3"
        ;;
    "whitelist")
        whitelist_token "$2"
        ;;
    "pause")
        pause_bridge
        ;;
    "unpause")
        unpause_bridge
        ;;
    "batch-size")
        set_batch_size "$2"
        ;;
    "balance")
        show_balance
        ;;
    "help"|"")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
