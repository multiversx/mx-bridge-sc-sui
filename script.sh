#!/bin/bash
set -euo pipefail

confirm() {
  read -p "$1 (y/n, default n): " answer
  answer=${answer:-n}
  [[ $answer == "y" || $answer == "Y" ]]
}

echo "=== FULL BRIDGE SETUP SCRIPT ==="
echo

# Step 1: Deploy
if confirm "Run deployment script (deploy.sh)?"; then
  ./deploy.sh
else
  echo "⏩ Skipping deploy.sh"
fi
echo

# Step 2: Token Setup
if confirm "Run token setup script (token-setup.sh)?"; then
  ./config/token-setup.sh
else
  echo "⏩ Skipping token-setup.sh"
fi
echo

# Step 3: Setters
if confirm "Run setters script (setters.sh)?"; then
  ./config/setters.sh
else
  echo "⏩ Skipping setters.sh"
fi
echo

echo "=== FULL SETUP COMPLETE ==="