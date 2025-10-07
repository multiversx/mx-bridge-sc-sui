#!/bin/bash
# Complete workflow: Generate addresses, get their peer IDs, and map them as relayers
# Usage: ./generate_and_map_relayers.sh [number_of_relayers]

set -euo pipefail

# Default number of relayer addresses to generate
NUMBER_RELAYERS=${1:-5}
CONFIG_FILE="./config/config.cfg"
LIST_JSON="./list.json"

echo "=== Complete Relayer Generation and Mapping Workflow ==="
echo "Generating $NUMBER_RELAYERS relayer addresses..."
echo ""

# Step 1: Generate new addresses
echo "🔄 Step 1: Generating new SUI addresses..."
addresses=()
failed_count=0

for ((i=1; i<=NUMBER_RELAYERS; i++)); do
    echo "Generating relayer address $i/$NUMBER_RELAYERS..."
    
    if output=$(sui client new-address ed25519 2>&1); then
        address=$(echo "$output" | grep -oE '0x[a-fA-F0-9]{64}' | head -n1)
        
        if [[ -n "$address" ]]; then
            addresses+=("$address")
            echo "✅ Address $i: $address"
        else
            echo "❌ Failed to extract address from output"
            ((failed_count++))
        fi
    else
        echo "❌ Failed to generate address $i"
        echo "$output"
        ((failed_count++))
    fi
    echo ""
done

success_count=${#addresses[@]}
echo "✅ Successfully generated: $success_count addresses"
echo "❌ Failed: $failed_count"
echo ""

if [[ $success_count -eq 0 ]]; then
    echo "❌ No addresses were generated successfully."
    exit 1
fi

# Step 2: Update the key list to include new addresses
echo "🔄 Step 2: Updating key list with new addresses..."
if sui keytool list --json > "$LIST_JSON"; then
    echo "✅ Key list updated in $LIST_JSON"
else
    echo "❌ Failed to update key list"
    exit 1
fi
echo ""

# Step 3: Find peer IDs for the generated addresses
echo "🔄 Step 3: Mapping addresses to peer IDs..."
temp_mappings=$(mktemp)
temp_summary=$(mktemp)

# Function to find peer ID for a given address
find_peer_id() {
    local address=$1
    local clean_address=${address#0x}
    
    python3 -c "
import json
import sys

try:
    with open('$LIST_JSON', 'r') as f:
        data = json.load(f)
    
    target_address = '$clean_address'.lower()
    
    for entry in data:
        entry_address = entry['suiAddress'][2:].lower() if entry['suiAddress'].startswith('0x') else entry['suiAddress'].lower()
        if entry_address == target_address:
            print(f\"{entry['peerId']}|{entry['alias']}\")
            sys.exit(0)
    
    print('NOT_FOUND')
    sys.exit(1)
except Exception as e:
    print('ERROR')
    sys.exit(1)
"
}

mapped_count=0
for i in "${!addresses[@]}"; do
    address="${addresses[$i]}"
    relayer_num=$((i+1))
    
    echo "Mapping RELAYER_$relayer_num: $address"
    
    result=$(find_peer_id "$address")
    
    if [[ "$result" == "NOT_FOUND" ]]; then
        echo "  ❌ No matching peer ID found for address: $address"
        echo "  💡 Try running 'sui keytool list --json > list.json' again"
    elif [[ "$result" == "ERROR" ]]; then
        echo "  ❌ Error processing address: $address"
    else
        IFS='|' read -r peer_id alias <<< "$result"
        echo "  ✅ Peer ID: $peer_id (alias: $alias)"
        
        # Store mapping
        echo "$relayer_num|$address|$alias|0x$peer_id" >> "$temp_mappings"
        echo "  RELAYER_$relayer_num: $address ($alias)" >> "$temp_summary"
        echo "  RELAYER_${relayer_num}_PK: 0x$peer_id" >> "$temp_summary"
        echo "" >> "$temp_summary"
        
        ((mapped_count++))
    fi
    echo ""
done

if [[ $mapped_count -eq 0 ]]; then
    echo "❌ No peer ID mappings could be created."
    rm -f "$temp_mappings" "$temp_summary"
    exit 1
fi

# Step 4: Update config file
echo "🔄 Step 4: Updating config file..."

# Create backup
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
echo "✅ Backup created: ${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

# Add new mappings to config
{
    echo ""
    echo "# New Relayer mappings (generated $(date))"
    while IFS='|' read -r relayer_num address alias peer_id; do
        echo "RELAYER_$relayer_num=\"$address\"  # $alias"
        echo "RELAYER_${relayer_num}_PK=\"$peer_id\"  # Peer ID for $alias"
    done < "$temp_mappings"
} >> "$CONFIG_FILE"

echo "✅ Config file updated with $mapped_count relayer mappings"
echo ""

# Step 5: Save generated addresses to timestamped file
output_file="./config/generated_relayers_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "# Generated Relayer Addresses - $(date)"
    echo "# Total: $success_count addresses, $mapped_count mapped"
    echo ""
    while IFS='|' read -r relayer_num address alias peer_id; do
        echo "RELAYER_$relayer_num=$address  # $alias"
        echo "RELAYER_${relayer_num}_PK=$peer_id  # Peer ID"
        echo ""
    done < "$temp_mappings"
} > "$output_file"

echo "📄 Relayer data saved to: $output_file"
echo ""

# Final summary
echo "========================================"
echo "🎉 Generation and Mapping Complete!"
echo "========================================"
echo "✅ Addresses generated: $success_count"
echo "✅ Successfully mapped: $mapped_count"
echo "❌ Failed mappings: $((success_count - mapped_count))"
echo ""
echo "Summary of mapped relayers:"
cat "$temp_summary"

echo "Next steps:"
echo "1. Review the updated config file: $CONFIG_FILE"
echo "2. The relayer data is also saved in: $output_file"
echo "3. Use the RELAYER_X and RELAYER_X_PK variables in your deployment scripts"

# Clean up
rm -f "$temp_mappings" "$temp_summary"