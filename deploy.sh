#!/usr/bin/env bash
set -euo pipefail

# Azure AI Security Sandbox - Deployment Script
# Deploys all infrastructure and the application using Bicep

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/infra"
SRC_DIR="$SCRIPT_DIR/src/backend"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Azure AI Security Sandbox - Deployment                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    if ! command -v az &>/dev/null; then
        echo -e "${RED}Error: Azure CLI 'az' is required but not installed.${NC}"
        echo "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi
    
    if ! az account show &>/dev/null; then
        echo -e "${YELLOW}Not logged into Azure. Initiating login...${NC}"
        az login
    fi
    
    echo -e "${GREEN}✓ Prerequisites met${NC}"
}

# Get deployment parameters
get_parameters() {
    echo
    echo -e "${YELLOW}Deployment Configuration${NC}"
    echo "─────────────────────────"
    
    # Environment name
    if [[ -z "${AZURE_ENV_NAME:-}" ]]; then
        read -rp "Enter environment name (e.g., dev, prod): " AZURE_ENV_NAME
        AZURE_ENV_NAME="${AZURE_ENV_NAME:-aisecurity}"
    fi
    echo -e "Environment: ${GREEN}$AZURE_ENV_NAME${NC}"
    
    # Location
    if [[ -z "${AZURE_LOCATION:-}" ]]; then
        echo
        echo "Available regions with Azure OpenAI support:"
        echo "  1) eastus2 (recommended)"
        echo "  2) eastus"
        echo "  3) westus"
        echo "  4) westus3"
        echo "  5) northcentralus"
        echo "  6) swedencentral"
        read -rp "Select region [1-6] or enter custom: " region_choice
        
        case "$region_choice" in
            1|"") AZURE_LOCATION="eastus2" ;;
            2) AZURE_LOCATION="eastus" ;;
            3) AZURE_LOCATION="westus" ;;
            4) AZURE_LOCATION="westus3" ;;
            5) AZURE_LOCATION="northcentralus" ;;
            6) AZURE_LOCATION="swedencentral" ;;
            *) AZURE_LOCATION="$region_choice" ;;
        esac
    fi
    echo -e "Location: ${GREEN}$AZURE_LOCATION${NC}"
    
    # OpenAI location (can be different)
    AZURE_OPENAI_LOCATION="${AZURE_OPENAI_LOCATION:-$AZURE_LOCATION}"
    
    # Defender options
    echo
    read -rp "Enable Defender for App Services (subscription-wide)? [Y/n]: " defender_appsvc
    ENABLE_DEFENDER_APPSVC="true"
    [[ "${defender_appsvc,,}" == "n" ]] && ENABLE_DEFENDER_APPSVC="false"
    
    read -rp "Enable Defender for Cosmos DB (subscription-wide)? [Y/n]: " defender_cosmos
    ENABLE_DEFENDER_COSMOS="true"
    [[ "${defender_cosmos,,}" == "n" ]] && ENABLE_DEFENDER_COSMOS="false"
}

# Deploy infrastructure
deploy_infrastructure() {
    echo
    echo -e "${YELLOW}Deploying infrastructure...${NC}"
    echo "This may take 10-15 minutes."
    echo
    
    DEPLOYMENT_NAME="aisecurity-${AZURE_ENV_NAME}-$(date +%Y%m%d-%H%M%S)"
    
    az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$AZURE_LOCATION" \
        --template-file "$INFRA_DIR/main.bicep" \
        --parameters \
            environmentName="$AZURE_ENV_NAME" \
            location="$AZURE_LOCATION" \
            openAiLocation="$AZURE_OPENAI_LOCATION" \
            enableDefenderForAppServices="$ENABLE_DEFENDER_APPSVC" \
            enableDefenderForCosmosDb="$ENABLE_DEFENDER_COSMOS" \
        --output json > /tmp/deployment_output.json
    
    # Extract outputs
    RESOURCE_GROUP=$(jq -r '.properties.outputs.RESOURCE_GROUP_NAME.value' /tmp/deployment_output.json)
    APP_SERVICE_NAME=$(jq -r '.properties.outputs.APP_SERVICE_NAME.value' /tmp/deployment_output.json)
    FRONTDOOR_URL=$(jq -r '.properties.outputs.FRONTDOOR_URL.value' /tmp/deployment_output.json)
    
    echo -e "${GREEN}✓ Infrastructure deployed${NC}"
    echo -e "  Resource Group: ${BLUE}$RESOURCE_GROUP${NC}"
}

# Deploy application code
deploy_application() {
    echo
    echo -e "${YELLOW}Deploying application code...${NC}"
    
    # Create a zip of the backend application
    DEPLOY_ZIP="/tmp/backend-deploy.zip"
    
    pushd "$SRC_DIR" > /dev/null
    zip -r "$DEPLOY_ZIP" . -x "*.pyc" -x "__pycache__/*" -x ".env" -x "*.egg-info/*" -x ".git/*"
    popd > /dev/null
    
    # Deploy to App Service
    az webapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_SERVICE_NAME" \
        --src "$DEPLOY_ZIP" \
        --timeout 600
    
    # Clean up
    rm -f "$DEPLOY_ZIP"
    
    echo -e "${GREEN}✓ Application deployed${NC}"
}

# Configure App Service access restrictions for Front Door
configure_frontdoor_access() {
    echo
    echo -e "${YELLOW}Configuring Front Door access restrictions...${NC}"
    
    # Get current restrictions
    CURRENT=$(az webapp config access-restriction show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_SERVICE_NAME" \
        --query "ipSecurityRestrictions" -o json 2>/dev/null || echo "[]")
    
    # Check if Front Door rule already exists
    if echo "$CURRENT" | grep -q "AllowFrontDoor"; then
        echo "Front Door access restriction already configured."
    else
        az webapp config access-restriction add \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APP_SERVICE_NAME" \
            --rule-name "AllowFrontDoor" \
            --action Allow \
            --service-tag AzureFrontDoor.Backend \
            --priority 100 \
            --output none
        
        echo -e "${GREEN}✓ Front Door access restriction configured${NC}"
    fi
}

# Print summary
print_summary() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  Deployment Complete! 🎉                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Resources:${NC}"
    echo -e "  Resource Group:  ${BLUE}$RESOURCE_GROUP${NC}"
    echo -e "  App Service:     ${BLUE}$APP_SERVICE_NAME${NC}"
    echo
    echo -e "${YELLOW}URLs:${NC}"
    echo -e "  Front Door:      ${GREEN}$FRONTDOOR_URL${NC}"
    echo -e "  API Docs:        ${GREEN}$FRONTDOOR_URL/docs${NC}"
    echo
    echo -e "${YELLOW}Security Features Enabled:${NC}"
    echo "  ✓ Azure Front Door with WAF (OWASP 3.2 + Bot Protection)"
    echo "  ✓ Defender for Storage (malware scanning + sensitive data)"
    echo "  ✓ Defender for AI (via Log Analytics)"
    [[ "$ENABLE_DEFENDER_APPSVC" == "true" ]] && echo "  ✓ Defender for App Services (subscription-wide)"
    [[ "$ENABLE_DEFENDER_COSMOS" == "true" ]] && echo "  ✓ Defender for Cosmos DB (subscription-wide)"
    echo "  ✓ Managed Identity (no secrets in code)"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Wait a few minutes for the app to warm up"
    echo "  2. Visit the Front Door URL to access the application"
    echo "  3. Upload documents to enable RAG functionality"
    echo
    echo -e "${YELLOW}To clean up resources:${NC}"
    echo "  ./cleanup.sh $AZURE_ENV_NAME"
    echo
    
    # Save state for cleanup
    cat > "$SCRIPT_DIR/.deployment_state.env" <<EOF
AZURE_ENV_NAME="$AZURE_ENV_NAME"
AZURE_LOCATION="$AZURE_LOCATION"
RESOURCE_GROUP="$RESOURCE_GROUP"
APP_SERVICE_NAME="$APP_SERVICE_NAME"
FRONTDOOR_URL="$FRONTDOOR_URL"
ENABLE_DEFENDER_APPSVC="$ENABLE_DEFENDER_APPSVC"
ENABLE_DEFENDER_COSMOS="$ENABLE_DEFENDER_COSMOS"
EOF
}

# Main execution
main() {
    check_prerequisites
    get_parameters
    deploy_infrastructure
    deploy_application
    configure_frontdoor_access
    print_summary
}

main "$@"
