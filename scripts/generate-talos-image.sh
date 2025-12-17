#!/bin/bash
set -e

# Use v1.11.5 as default, but allow overriding via environment variable
TALOS_VERSION="${TALOS_VERSION:-v1.11.5}"
SCHEMATIC_ID="${SCHEMATIC_ID:-}"

# Only generate a new schematic ID if one isn't already provided
if [ -z "$SCHEMATIC_ID" ]; then
    # Post a customization schematic to the Talos Factory API
    SCHEMATIC_RESPONSE=$(curl -s -X POST \
        --data-binary @- \
        https://factory.talos.dev/schematics <<SCHEMATIC
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/intel-ucode
      - siderolabs/i915-ucode
      - siderolabs/iscsi-tools
      - siderolabs/util-linux-tools
SCHEMATIC
)

    # Extract the schematic ID from the JSON response
    SCHEMATIC_ID=$(echo "$SCHEMATIC_RESPONSE" | jq -r '.id')

    # Provide a known-good fallback Schematic ID if the API call fails
    if [ -z "$SCHEMATIC_ID" ] || [ "$SCHEMATIC_ID" == "null" ]; then
        # Fallback schematic ID for these extensions (regenerate if version changes)
        SCHEMATIC_ID="4ea1b20ff3e83bcbff11c768b45ab3c2c4cfa54bbd5cf4e90b25a815b9b90b1c"
    fi
fi

# Output the final JSON for Terraform to consume
cat <<JSON
{
  "version": "$TALOS_VERSION",
  "schematic_id": "$SCHEMATIC_ID"
}
JSON
