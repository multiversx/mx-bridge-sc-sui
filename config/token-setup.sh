#!/bin/bash
set -euo pipefail

# Load config
source ./config.cfg

confirm() {
  read -p "$1 (y/n, default n): " answer
  answer=${answer:-n}
  [[ $answer == "y" || $answer == "Y" ]]
}

echo "=== TOKEN SETUP SCRIPT ==="
echo "Package: $PACKAGE_ID"
echo "Safe: $SAFE_ID"
echo "AdminCap: $ADMIN_CAP_ID"
echo "Token: $TOKEN_TYPE"
echo

# ===== STEP 1: Whitelist Token =====
if confirm "Step 1: Whitelist token?"; then
  echo "Calling whitelist_token..."
  WHITELIST_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function whitelist_token \
    --type-args "$TOKEN_TYPE" \
    --args "$SAFE_ID" "$ADMIN_CAP_ID" "$TOKEN_MIN" "$TOKEN_MAX" "$TOKEN_IS_NATIVE" "$TOKEN_IS_LOCKED" \
    --gas-budget 200000000 --json 2>/dev/null | jq -c .)
  echo "$WHITELIST_OUTPUT" > whitelist_output.json
  echo "✅ Token whitelisted."
else
  echo "Skipping whitelist."
fi

# ===== STEP 2: Initialize Supply =====
if confirm "Step 2: Initialize supply?"; then
  echo "Calling init_supply..."
  INIT_SUPPLY_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function init_supply \
    --type-args "$COIN_TYPE" \
    --args "$ADMIN_CAP_ID" "$SAFE_ID" "$COIN_OBJECT" \
    --gas-budget 200000000 --json 2>/dev/null | jq -c .)
  echo "$INIT_SUPPLY_OUTPUT" > init_supply_output.json
  echo "✅ Token supply initialized."
else
  echo "Skipping init_supply."
fi

echo "=== Token Setup Complete ==="