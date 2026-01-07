#!/usr/bin/env bash
set -euo pipefail

# Azure AI Security Sandbox - Cleanup Script
# Removes all deployed resources and optionally reverts Defender settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.deployment_state.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Azure AI Security Sandbox - Cleanup                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

# Load state from deployment or use parameter
AZURE_ENV_NAME="${1:-}"

if [[ -z "$AZURE_ENV_NAME" ]] && [[ -f "$STATE_FILE" ]]; then
    source "$STATE_FILE"
    echo -e "Loaded state from previous deployment."
fi

if [[ -z "$AZURE_ENV_NAME" ]]; then
    read -rp "Enter environment name to clean up: " AZURE_ENV_NAME
fi

if [[ -z "$AZURE_ENV_NAME" ]]; then
    echo -e "${RED}Error: Environment name is required.${NC}"
    exit 1
fi

# Construct resource group name (matches Bicep naming convention)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aisecurity-$AZURE_ENV_NAME}"

echo -e "Environment: ${YELLOW}$AZURE_ENV_NAME${NC}"
echo -e "Resource Group: ${YELLOW}$RESOURCE_GROUP${NC}"
echo

# Check if resource group exists
check_resource_group() {
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        echo -e "${YELLOW}Resource group '$RESOURCE_GROUP' not found.${NC}"
        echo "Nothing to clean up."
        exit 0
    fi
}

# List resources to be deleted
list_resources() {
    echo -e "${YELLOW}Resources to be deleted:${NC}"
    echo "─────────────────────────"
    
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type}" \
        --output table
    
    echo
}

# Confirm deletion
confirm_deletion() {
    echo -e "${RED}WARNING: This will permanently delete all resources in '$RESOURCE_GROUP'.${NC}"
    read -rp "Are you sure you want to continue? [y/N]: " confirm
    
    if [[ "${confirm,,}" != "y" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
}

# Delete resource group
delete_resources() {
    echo
    echo -e "${YELLOW}Deleting resource group '$RESOURCE_GROUP'...${NC}"
    echo "This may take several minutes."
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    echo -e "${GREEN}✓ Resource group deletion initiated${NC}"
    echo "  The deletion is running in the background."
}

# Handle Defender plans
handle_defender_plans() {
    echo
    echo -e "${YELLOW}Defender Plan Settings${NC}"
    echo "─────────────────────────"
    echo "If you enabled subscription-wide Defender plans via enable-defender.sh,"
    echo "you can roll them back by running:"
    echo "  ./scripts/disable-defender.sh --confirm"
    echo
    echo -e "${YELLOW}Note:${NC} These are subscription-wide settings that affect all resources."
    echo "They will NOT be automatically disabled to avoid impacting other workloads."
}

# Clean up Front Door if it exists at subscription level
cleanup_frontdoor() {
    # Front Door profiles are in the resource group, so they get deleted automatically
    # This function is here for any additional cleanup if needed
    :
}

# Clean up state file
cleanup_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        echo -e "${GREEN}✓ Cleaned up local state file${NC}"
    fi
}

# Print summary
print_summary() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   Cleanup Complete! 🧹                       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "The resource group deletion has been initiated and is running"
    echo "in the background. It may take 5-10 minutes to complete."
    echo
    echo "To verify deletion status:"
    echo -e "  ${BLUE}az group show --name $RESOURCE_GROUP${NC}"
    echo
    echo "Once complete, you'll receive an error indicating the resource"
    echo "group doesn't exist - that's expected and confirms deletion."
    echo
}

# Main execution
main() {
    # Check Azure CLI login
    if ! az account show &>/dev/null; then
        echo -e "${YELLOW}Not logged into Azure. Initiating login...${NC}"
        az login
    fi
    
    check_resource_group
    list_resources
    confirm_deletion
    delete_resources
    handle_defender_plans
    cleanup_state
    print_summary
}

main "$@"
