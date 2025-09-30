#!/bin/bash
set -euo pipefail

# Load config
source ./config.cfg

confirm() {
  read -p "$1 (y/n, default n): " answer
  answer=${answer:-n}
  [[ $answer == "y" || $answer == "Y" ]]
}

echo "=== SUI SETTERS SCRIPT ==="
echo "Package: $PACKAGE_ID"
echo "Safe: $SAFE_ID"
echo "AdminCap: $ADMIN_CAP_ID"
echo

# ===== Step 1: Set Policy Cap =====
if confirm "Call set_policy_cap?"; then
  echo "Calling set_policy_cap..."
  SET_POLICY_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function set_policy_cap \
    --args "$ADMIN_CAP_ID" "$SAFE_ID" "$POLICY_CAP_ID" \
    --gas-budget 200000000 --json 2>/dev/null | jq -c .)
  echo "$SET_POLICY_OUTPUT" > set_policy_output.json
  echo "✅ Policy cap set."
else
  echo "Skipping set_policy_cap."
fi

# ===== Step 2: Set Treasury Cap =====
if confirm "Call set_treasury_cap?"; then
  echo "Calling set_treasury_cap..."
  SET_TREASURY_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function set_treasury_cap \
    --args "$ADMIN_CAP_ID" "$SAFE_ID" "$TREASURY_CAP_ID" \
    --gas-budget 200000000 --json 2>/dev/null | jq -c .)
  echo "$SET_TREASURY_OUTPUT" > set_treasury_output.json
  echo "✅ Treasury cap set."
else
  echo "Skipping set_treasury_cap."
fi

# ===== Step 3: Set Stake Address =====
if confirm "Call set_stake_address?"; then
  echo "Calling set_stake_address..."
  SET_STAKE_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module safe \
    --function set_stake_address \
    --args "$ADMIN_CAP_ID" "$POLICY_ID" "$SAFE_ID" "$STAKE_ADDR" \
    --gas-budget 200000000 --json 2>/dev/null | jq -c .)
  echo "$SET_STAKE_OUTPUT" > set_stake_output.json
  echo "✅ Stake address set."
else
  echo "Skipping set_stake_address."
fi

echo "=== Setters Complete ==="