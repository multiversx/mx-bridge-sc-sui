#!/bin/bash
set -e

# Make script aware of its location
SCRIPTPATH="$( cd "$(dirname -- "$0")" ; pwd -P )"

source $SCRIPTPATH/config/config.cfg
source $SCRIPTPATH/functions.sh
source $SCRIPTPATH/config/helper_functions.cfg

# Check if argument is provided
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <command>"
  echo ""
  echo "Available commands:"
  echo "  deploy               - Deploy bridge contracts"
  echo "  whitelist-xmn        - Whitelist XMN token"
  echo "  whitelist-bridge     - Whitelist Bridge token"
  echo "  init-supply-xmn      - Initialize XMN supply"
  echo "  init-supply-bridge   - Initialize Bridge supply"
  echo "  add-relayer          - Add a relayer"
  echo "  remove-relayer       - Remove a relayer"
  echo "  pause-bridge         - Pause bridge operations"
  echo "  unpause-bridge       - Unpause bridge operations"
  echo "  set-quorum           - Set bridge quorum"
  echo ""
  exit 1
fi

case "$1" in

### DEPLOYMENT
'deploy')
  confirmation deploy
  ;;

### TOKEN MANAGEMENT
'whitelist-xmn')
  confirmation whitelist-xmn
  ;;

'whitelist-bridge')
  confirmation whitelist-bridge
  ;;

'whitelist-token')
  echo "Whitelisting custom token..."
  read -p "Enter token type (e.g., 0x123::token::TOKEN): " TOKEN_TYPE
  read -p "Enter min amount [1]: " MIN_AMOUNT
  read -p "Enter max amount [1000000]: " MAX_AMOUNT
  read -p "Is native token? [true]: " IS_NATIVE
  read -p "Is locked token? [false]: " IS_LOCKED
  confirmation whitelist "$TOKEN_TYPE" "${MIN_AMOUNT:-1}" "${MAX_AMOUNT:-1000000}" "${IS_NATIVE:-true}" "${IS_LOCKED:-false}"
  ;;

'remove-whitelist')
  confirmation remove-whitelist
  ;;

'init-supply-xmn')
  confirmation init-supply-xmn
  ;;

'init-supply-bridge')
  confirmation init-supply-bridge
  ;;

'init-supply')
  read -p "Enter token type: " TOKEN_TYPE
  read -p "Enter treasury object: " TREASURY_OBJECT
  confirmation init-supply "$TOKEN_TYPE" "$TREASURY_OBJECT"
  ;;

### RELAYER MANAGEMENT
'add-relayer')
  read -p "Enter relayer public key: " PUBLIC_KEY
  confirmation add-relayer "$PUBLIC_KEY"
  ;;

'remove-relayer')
  read -p "Enter relayer address: " RELAYER_ADDRESS
  confirmation remove-relayer "$RELAYER_ADDRESS"
  ;;

### BRIDGE OPERATIONS
'pause-bridge')
  confirmation pause-bridge
  ;;

'unpause-bridge')
  confirmation unpause-bridge
  ;;

'set-quorum')
  read -p "Enter new quorum value: " NEW_QUORUM
  confirmation set-quorum "$NEW_QUORUM"
  ;;

### SAFE OPERATIONS
'set-batch-size')
  read -p "Enter new batch size: " BATCH_SIZE
  confirmation set-batch-size "$BATCH_SIZE"
  ;;

'set-batch-timeout')
  read -p "Enter timeout in milliseconds: " TIMEOUT
  confirmation set_batch_timeout "$TIMEOUT"
  ;;

'pause-safe')
  confirmation pause-safe
  ;;

'unpause-safe')
  confirmation unpause-safe
  ;;

### UTILITIES
'check-prerequisites')
  confirmation check-prerequisites
  ;;

'get-status')
  confirmation get-bridge-status
  ;;

'status')
  echo "========================================"
  echo "BRIDGE STATUS"
  echo "========================================"
  echo "Package ID: $PACKAGE_ID"
  echo "Upgrade Cap: $UPGRADE_CAP_ID"
  echo "Safe ID: $SAFE_ID"
  echo "Bridge Cap: $BRIDGE_CAP_ID"
  echo "Bridge ID: $BRIDGE_ID"
  echo "FromCoinCap: $FROM_COIN_CAP"
  echo ""
  echo "XMN Token Configuration:"
  echo "  Type: $TOKEN_TYPE_XMN"
  echo "  Min: $TOKEN_MIN_XMN"
  echo "  Max: $TOKEN_MAX_XMN"
  echo "  Native: $TOKEN_IS_NATIVE_XMN"
  echo "  Locked: $TOKEN_IS_LOCKED_XMN"
  echo "  Treasury: $COIN_ID_XMN"
  echo ""
  echo "Bridge Token Configuration:"
  echo "  Type: $TOKEN_TYPE_BRIDGE"
  echo "  Min: $TOKEN_MIN_BRIDGE"
  echo "  Max: $TOKEN_MAX_BRIDGE"
  echo "  Native: $TOKEN_IS_NATIVE_BRIDGE"
  echo "  Locked: $TOKEN_IS_LOCKED_BRIDGE"
  echo "  Treasury: $COIN_ID_BRIDGE"
  echo ""
  echo "Relayer Public Keys:"
  echo "  PK1: $PK_1"
  echo "  PK2: $PK_2"
  echo "  PK3: $PK_3"
  echo "  PK4: $PK_4"
  echo "Quorum: $QUORUM"
  ;;

*)
  echo "Usage: Invalid choice: '"$1"'"
  echo -e
  echo "Available functions:"
  echo "  deploy                       - Deploy bridge contracts"
  echo "  whitelist-xmn                - Whitelist XMN token"
  echo "  whitelist-bridge             - Whitelist Bridge token"
  echo "  whitelist <token> [args...]  - Whitelist custom token"
  echo "  remove-whitelist             - Remove token from whitelist"
  echo "  add-relayer <public_key>     - Add a relayer"
  echo "  remove-relayer <address>     - Remove a relayer"
  echo "  init-supply-xmn              - Initialize XMN supply"
  echo "  init-supply-bridge           - Initialize Bridge supply"
  echo "  init-supply <token> <treasury> - Initialize custom supply"
  echo "  pause-bridge                 - Pause the bridge"
  echo "  unpause-bridge               - Unpause the bridge"
  echo "  set-quorum <value>           - Set new quorum value"
  echo "  set-batch-size <size>        - Set new batch size"
  echo "  set-batch-timeout <ms>       - Set batch timeout in milliseconds"
  echo "  pause-safe                   - Pause the safe"
  echo "  unpause-safe                 - Unpause the safe"
  echo "  check-prerequisites          - Check environment prerequisites"
  echo "  get-status                   - Get current bridge status"
  echo -e
  ;;

esac