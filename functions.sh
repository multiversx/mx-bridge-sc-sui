#!/bin/bash
# Copyright 2025 MultiversX
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

# Load config file
source ./config/config.cfg
source ./config/helper_functions.cfg

# Default gas budget
GAS_BUDGET_DEFAULT=200000000

# Utility functions
update_config() {
  local key="$1"
  local value="$2"
  local config_file="./config/config.cfg"
  
  if grep -q "^${key}=" "$config_file"; then
    sed -i.bak "s/^${key}=.*/${key}=${value}/" "$config_file"
  else
    echo "${key}=${value}" >> "$config_file"
  fi
  echo "Updated ${key}=${value} in config.cfg"
}

extract_object_id() {
  local output="$1"
  local object_type="$2"
  echo "$output" | jq -r --arg type "$object_type" '.objectChanges[] | select(.objectType != null and (.objectType | contains($type))) | .objectId'
}

save_deployment_data() {
  echo "Saving deployment data to $OUTPUT_FILE..."
  cat > "$OUTPUT_FILE" <<EOF
{
  "PackageId": "$PACKAGE_ID",
  "UpgradeCap": "$UPGRADE_CAP_ID", 
  "BridgeSafe": "$SAFE_ID",
  "BridgeCap": "$BRIDGE_CAP_ID",
  "Bridge": "$BRIDGE_ID",
  "FromCoinCap": "$FROM_COIN_CAP"
}
EOF
  echo "Data saved to $OUTPUT_FILE"
}

# Main deployment function
function deploy() {
  echo "=== SUI Bridge Deployment ==="
  
  # Step 1: Publish package
  echo "Publishing package with unpublished dependencies..."
  sui client publish --json > ./config/publish_output.json
  
  PUBLISH_OUTPUT=$(cat ./config/publish_output.json)
  
  # Extract package ID and upgrade cap
  PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
  UPGRADE_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("package::UpgradeCap"))) | .objectId')
  
  echo "Package ID: $PACKAGE_ID"
  echo "Upgrade Cap: $UPGRADE_CAP_ID"
  
  # Update config with package ID and upgrade cap
  update_config "PACKAGE_ID" "$PACKAGE_ID"
  update_config "UPGRADE_CAP_ID" "$UPGRADE_CAP_ID"
  
  # Step 2: Initialize safe
  echo "Initializing safe..."
  echo "Using FROM_COIN_CAP: $FROM_COIN_CAP"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function initialize \
    --args "$FROM_COIN_CAP" \
    --gas-budget $GAS_BUDGET_DEFAULT \
    --json > ./config/safe_initialize_output.json
    
  # Extract safe ID and bridge cap
  SAFE_INIT_OUTPUT=$(cat ./config/safe_initialize_output.json)
  SAFE_ID=$(extract_object_id "$SAFE_INIT_OUTPUT" "safe::BridgeSafe")
  BRIDGE_CAP_ID=$(extract_object_id "$SAFE_INIT_OUTPUT" "roles::BridgeCap")
  
  echo "Bridge Safe ID: $SAFE_ID"
  echo "Bridge Cap: $BRIDGE_CAP_ID"
  
  # Update config
  update_config "SAFE_ID" "$SAFE_ID"
  update_config "BRIDGE_CAP_ID" "$BRIDGE_CAP_ID"
  
  # Step 3: Initialize bridge
  echo "Initializing bridge..."
  echo "Using public keys: [$PK_1, $PK_2, $PK_3]"
  echo "Quorum: $QUORUM"
  echo "Safe ID: $SAFE_ID"
  echo "Bridge Cap: $BRIDGE_CAP_ID"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module bridge \
    --function initialize \
    --args \
      $PUBKEYS \
      "$QUORUM" \
      "$SAFE_ID" \
      "$BRIDGE_CAP_ID" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/bridge_initialize_output.json
    
  # Extract bridge ID
  BRIDGE_INIT_OUTPUT=$(cat ./config/bridge_initialize_output.json)
  BRIDGE_ID=$(extract_object_id "$BRIDGE_INIT_OUTPUT" "bridge::Bridge")
  
  echo "Bridge ID: $BRIDGE_ID"
  
  # Update config
  update_config "BRIDGE_ID" "$BRIDGE_ID"
  
  # Step 4: Set bridge address in safe
  echo "Setting bridge address in safe..."
  echo "Safe ID: $SAFE_ID"
  echo "Bridge ID: $BRIDGE_ID"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function set_bridge_addr \
    --args "$SAFE_ID" "$BRIDGE_ID" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/set_bridge_output.json
  
    echo "✅ Bridge address set in safe"
  
  # Save deployment data
  save_deployment_data
  
  echo "=== Deployment Complete ==="
}

# Whitelist XMN token function
function whitelist-xmn() {
  echo "=== Whitelisting XMN Token ==="
  
  echo "Whitelisting token: $TOKEN_TYPE_XMN"
  echo "Min amount: $TOKEN_MIN_XMN"
  echo "Max amount: $TOKEN_MAX_XMN"
  echo "Native: $TOKEN_IS_NATIVE_XMN"
  echo "Locked: $TOKEN_IS_LOCKED_XMN"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function whitelist_token \
    --type-args "$TOKEN_TYPE_XMN" \
    --args \
      "$SAFE_ID" \
      "$TOKEN_MIN_XMN" \
      "$TOKEN_MAX_XMN" \
      "$TOKEN_IS_NATIVE_XMN" \
      "$TOKEN_IS_LOCKED_XMN" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/whitelist_xmn_output.json
  
  echo "✅ XMN Token whitelisted successfully"
}

# Whitelist Bridge token function
function whitelist-bridge() {
  echo "=== Whitelisting Bridge Token ==="
  
  echo "Whitelisting token: $TOKEN_TYPE_BRIDGE"
  echo "Min amount: $TOKEN_MIN_BRIDGE"
  echo "Max amount: $TOKEN_MAX_BRIDGE"
  echo "Native: $TOKEN_IS_NATIVE_BRIDGE"
  echo "Locked: $TOKEN_IS_LOCKED_BRIDGE"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function whitelist_token \
    --type-args "$TOKEN_TYPE_BRIDGE" \
    --args \
      "$SAFE_ID" \
      "$TOKEN_MIN_BRIDGE" \
      "$TOKEN_MAX_BRIDGE" \
      "$TOKEN_IS_NATIVE_BRIDGE" \
      "$TOKEN_IS_LOCKED_BRIDGE" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/whitelist_bridge_output.json
  
  echo "✅ Bridge Token whitelisted successfully"
}

# Generic whitelist token function
function whitelist() {
  echo "=== Whitelisting Token ==="
  
  if [[ -z "$1" ]]; then
    echo "Usage: whitelist <token_type> [min_amount] [max_amount] [is_native] [is_locked]"
    echo "Example: whitelist \"0x123::token::TOKEN\" 1 1000000 true false"
    exit 1
  fi
  
  local TOKEN_TYPE="$1"
  local MIN_AMOUNT="${2:-1}"
  local MAX_AMOUNT="${3:-1000000}"
  local IS_NATIVE="${4:-true}"
  local IS_LOCKED="${5:-false}"
  
  echo "Whitelisting token: $TOKEN_TYPE"
  echo "Min amount: $MIN_AMOUNT"
  echo "Max amount: $MAX_AMOUNT"
  echo "Native: $IS_NATIVE"
  echo "Locked: $IS_LOCKED"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function whitelist_token \
    --type-args "$TOKEN_TYPE" \
    --args \
      "$SAFE_ID" \
      "$MIN_AMOUNT" \
      "$MAX_AMOUNT" \
      "$IS_NATIVE" \
      "$IS_LOCKED" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/whitelist_output.json
  
  echo "$WHITELIST_OUTPUT" > ./config/whitelist_output.json
  echo "✅ Token whitelisted successfully"
}

# Remove whitelist function
function remove-whitelist() {
  echo "=== Removing Token from Whitelist ==="
  
  if [[ -z "$TOKEN_TYPE" ]]; then
    echo "Error: TOKEN_TYPE must be set in config.cfg"
    exit 1
  fi
  
  echo "Removing token from whitelist: $TOKEN_TYPE"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function remove_token_from_whitelist \
    --type-args "$TOKEN_TYPE" \
    --args \
      "$SAFE_ID" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/remove_whitelist_output.json
  
  echo "✅ Token removed from whitelist successfully"
}

# Add relayer function
function add-relayer() {
  echo "=== Adding Relayer ==="
  
  if [[ -z "$1" ]]; then
    echo "Usage: add_relayer <public_key>"
    echo "Example: add_relayer 0x123..."
    exit 1
  fi
  
  local PUBLIC_KEY="$1"
  echo "Adding relayer with public key: $PUBLIC_KEY"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module bridge \
    --function add_relayer \
    --args \
      "$BRIDGE_ID" \
      "$BRIDGE_CAP_ID" \
      "$PUBLIC_KEY" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/add_relayer_output.json
  
  echo "✅ Relayer added successfully"
}

# Remove relayer function
function remove-relayer() {
  echo "=== Removing Relayer ==="
  
  if [[ -z "$1" ]]; then
    echo "Usage: remove_relayer <relayer_address>"
    echo "Example: remove_relayer 0x123..."
    exit 1
  fi
  
  local RELAYER_ADDRESS="$1"
  echo "Removing relayer: $RELAYER_ADDRESS"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module bridge \
    --function remove_relayer \
    --args \
      "$BRIDGE_ID" \
      "$BRIDGE_CAP_ID" \
      "$RELAYER_ADDRESS" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/remove_relayer_output.json
  
  echo "✅ Relayer removed successfully"
}

# Initialize supply function
# Initialize supply for XMN token
function init-supply-xmn() {
  echo "=== Initializing XMN Token Supply ==="
  
  echo "Token type: $TOKEN_TYPE_XMN"
  echo "Safe ID: $SAFE_ID"
  echo "Treasury: $COIN_ID_XMN"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function init_supply \
    --type-args "$TOKEN_TYPE_XMN" \
    --args "$SAFE_ID" "$COIN_ID_XMN" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/init_supply_xmn_output.json
  
  echo "✅ XMN Supply initialized successfully"
}

# Initialize supply for Bridge token
function init-supply-bridge() {
  echo "=== Initializing Bridge Token Supply ==="
  
  echo "Token type: $TOKEN_TYPE_BRIDGE"
  echo "Safe ID: $SAFE_ID"
  echo "Treasury: $COIN_ID_BRIDGE"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function init_supply \
    --type-args "$TOKEN_TYPE_BRIDGE" \
    --args "$SAFE_ID" "$COIN_ID_BRIDGE" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/init_supply_bridge_output.json
  
  echo "✅ Bridge Token Supply initialized successfully"
}

# Generic init supply function
function init-supply() {
  echo "=== Initializing Token Supply ==="
  
  if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: init_supply <token_type> <treasury_object>"
    echo "Example: init_supply \"0x123::token::TOKEN\" \"0x456...\""
    echo ""
    echo "Or use specific functions:"
    echo "  init_supply_xmn"
    echo "  init_supply_bridge"
    exit 1
  fi
  
  local TOKEN_TYPE="$1"
  local TREASURY_OBJECT="$2"
  
  echo "Token type: $TOKEN_TYPE"
  echo "Safe ID: $SAFE_ID"
  echo "Treasury: $TREASURY_OBJECT"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function init_supply \
    --type-args "$TOKEN_TYPE" \
    --args "$SAFE_ID" "$TREASURY_OBJECT" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/init_supply_output.json
  
  echo "✅ Supply initialized successfully"
}

function pause-bridge() {  
  echo "=== Pausing Bridge ==="
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module bridge \
    --function pause_contract \
    --args \
      "$BRIDGE_ID" \
      "$SAFE_ID" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/pause_bridge_output.json
  
  echo "✅ Bridge paused successfully"
}

# Unpause bridge function
function unpause-bridge() {
  echo "=== Unpausing Bridge ==="
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module bridge \
    --function unpause_contract \
    --args \
      "$BRIDGE_ID" \
      "$SAFE_ID" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/unpause_bridge_output.json
  
  echo "✅ Bridge unpaused successfully"
}

# Set quorum function
function set-quorum() {
  echo "=== Setting Bridge Quorum ==="
  
  if [[ -z "$1" ]]; then
    echo "Usage: set_quorum <new_quorum>"
    exit 1
  fi
  
  local NEW_QUORUM="$1"
  echo "Setting quorum to: $NEW_QUORUM"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module bridge \
    --function set_quorum \
    --args \
      "$BRIDGE_ID" \
      "$BRIDGE_CAP_ID" \
      "$NEW_QUORUM" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/set_quorum_output.json
    
  # Update config file
  update_config "QUORUM" "$NEW_QUORUM"
  
  echo "✅ Quorum set to $NEW_QUORUM successfully"
}

# Set batch size function
function set-batch-size() {
  echo "=== Setting Safe Batch Size ==="
  
  if [[ -z "$1" ]]; then
    echo "Usage: set_batch_size <new_batch_size>"
    exit 1
  fi
  
  local NEW_BATCH_SIZE="$1"
  echo "Setting batch size to: $NEW_BATCH_SIZE"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function set_batch_size \
    --args \
      "$SAFE_ID" \
      "$BRIDGE_CAP_ID" \
      "$NEW_BATCH_SIZE" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/set_batch_size_output.json
  
  echo "✅ Batch size set to $NEW_BATCH_SIZE successfully"
}

# Set batch timeout function  
function set-batch-timeout() {
  echo "=== Setting Safe Batch Timeout ==="
  
  if [[ -z "$1" ]]; then
    echo "Usage: set_batch_timeout <timeout_ms>"
    exit 1
  fi
  
  local TIMEOUT_MS="$1"
  echo "Setting batch timeout to: $TIMEOUT_MS ms"
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function set_batch_timeout \
    --args \
      "$SAFE_ID" \
      "$BRIDGE_CAP_ID" \
      "$TIMEOUT_MS" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/set_batch_timeout_output.json
  
  echo "✅ Batch timeout set to $TIMEOUT_MS ms successfully"
}

# Pause safe function
function pause-safe() {
  echo "=== Pausing Safe ==="
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function pause_contract \
    --args \
      "$SAFE_ID" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/pause_safe_output.json
  
  echo "✅ Safe paused successfully"
}

# Unpause safe function
function unpause-safe() {
  echo "=== Unpausing Safe ==="
  
  sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function unpause_contract \
    --args \
      "$SAFE_ID" \
    --gas-budget $GAS_BUDGET_DEFAULT --json > ./config/unpause_safe_output.json
  
  echo "✅ Safe unpaused successfully"
}

# Get bridge status function
function get-bridge-status() {
  echo "=== Getting Bridge Status ==="
  
  # Query bridge object
  sui client object "$BRIDGE_ID" --json > ./config/bridge_status.json
  
  # Query safe object  
  sui client object "$SAFE_ID" --json > ./config/safe_status.json
  
  echo "Bridge and Safe status saved to config/bridge_status.json and config/safe_status.json"
}

# Check prerequisites function
function check-prerequisites() {
  echo "=== Checking Prerequisites ==="
  
  # Check if required tools are installed
  command -v sui >/dev/null || { echo "Error: sui CLI is required"; exit 1; }
  command -v jq >/dev/null || { echo "Error: jq is required"; exit 1; }
  
  # Check if config file exists
  if [[ ! -f "./config/config.cfg" ]]; then
    echo "Error: config/config.cfg not found"
    exit 1
  fi
  
  # Check if key variables are set
  if [[ -z "$PACKAGE_ID" && "$1" != "deploy" ]]; then
    echo "Warning: PACKAGE_ID not set. Run deployment first."
  fi
  
  echo "✅ Prerequisites check passed"
}