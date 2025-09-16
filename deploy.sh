#!/bin/bash
set -euo pipefail

# Load config file
source ./config/config.cfg

confirm() {
  read -p "$1 (y/n, default n): " answer
  answer=${answer:-n}
  [[ $answer == "y" || $answer == "Y" ]]
}

extract_json_field() {
  echo "$1" | jq -r "$2"
}

save_data() {
  echo "Saving deployment data to $OUTPUT_FILE..."
  cat > "$OUTPUT_FILE" <<EOF
{
  "PackageId": "$PACKAGE_ID",
  "BridgeSafe": "$SAFE_ID",
  "BridgeCap": "$BRIDGE_CAP_ID",
  "AdminCap": "$ADMIN_CAP_ID",
  "TokenPolicy": "$POLICY_ID",
  "TokenPolicyCap": "$POLICY_CAP_ID",
  "TreasuryCap": "$TREASURY_CAP_ID",
  "Bridge": "$BRIDGE_ID"
}
EOF
  echo "Data saved to $OUTPUT_FILE"
}

echo "=== SUI Deployment Script ==="

# ===== STEP 1: Publish the package =====
if confirm "Step 1: Publish the package?"; then
  echo "Publishing package..."
  PUBLISH_OUTPUT=$(sui client publish --json)
  echo "$PUBLISH_OUTPUT" > publish_output.json

PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.type=="published") | .packageId')
SAFE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("safe::BridgeSafe"))) | .objectId')
BRIDGE_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("roles::BridgeCap"))) | .objectId')
ADMIN_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("roles::AdminCap"))) | .objectId')
POLICY_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("token::TokenPolicy<"))) | .objectId')
POLICY_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("token::TokenPolicyCap<"))) | .objectId')
TREASURY_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("coin::TreasuryCap<"))) | .objectId')

  echo "Package ID: $PACKAGE_ID"
  echo "BridgeSafe: $SAFE_ID"
  echo "BridgeCap: $BRIDGE_CAP_ID"
  echo "AdminCap: $ADMIN_CAP_ID"
  echo "TokenPolicy: $POLICY_ID"
  echo "TokenPolicyCap: $POLICY_CAP_ID"
  echo "TreasuryCap: $TREASURY_CAP_ID"
else
  echo "Skipping publish."
  exit 0
fi

# ===== STEP 2: Call initialize =====
if confirm "Step 2: Call initialize?"; then
  echo "Calling initialize..."
  INIT_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module bridge \
    --function initialize \
    --args "[$RELAYER_1, $RELAYER_2, $RELAYER_3, $RELAYER_4]" \
    "[$PK_1, $PK_2, $PK_3, $PK_4]" \
    "$QUORUM" \
    "$SAFE_ID" \
    "$BRIDGE_CAP_ID" \
    --gas-budget 200000000 --json)
  echo "$INIT_OUTPUT" > ./config/initialize_output.json

BRIDGE_ID=$(echo "$INIT_OUTPUT" | jq -r \
  '.objectChanges[] | select(.objectType != null and (.objectType | endswith("::bridge::Bridge"))) | .objectId')
else
  echo "Skipping initialize."
  exit 0
fi

# ===== STEP 3: Call set_bridge_addr =====
if confirm "Step 3: Call set_bridge_addr?"; then
  echo "Calling set_bridge_addr..."
  SET_BRIDGE_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function set_bridge_addr \
    --args "$SAFE_ID" "$ADMIN_CAP_ID" "$BRIDGE_ID" \
    --gas-budget 200000000 --json)
  echo "$SET_BRIDGE_OUTPUT" > ./config/set_bridge_output.json
else
  echo "Skipping set_bridge_addr."
  exit 0
fi

# ===== Save All IDs =====
save_data
echo "=== Deployment Complete ==="