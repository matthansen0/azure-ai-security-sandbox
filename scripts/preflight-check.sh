#!/usr/bin/env bash
# preflight-check.sh
# Checks regional quota for Azure AI Search and Azure OpenAI (gpt-4o) before
# attempting a full deployment. Emits actionable errors + region-change
# instructions when quota is insufficient.
#
# Exits 0 on success, 1 on quota/capacity issue.

set -u

LOCATION="${AZURE_LOCATION:-}"
OPENAI_LOCATION="${AZURE_OPENAI_LOCATION:-$LOCATION}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null)}"

# Required gpt-4o capacity (TPM in thousands) - must match infra/modules/ai-services.bicep
REQUIRED_GPT4O_CAPACITY=10
REQUIRED_EMBEDDING_CAPACITY=50

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

FAIL=0

if [ -z "$LOCATION" ] || [ -z "$SUBSCRIPTION_ID" ]; then
  echo -e "${YELLOW}⚠️  Skipping preflight: AZURE_LOCATION or subscription not set.${NC}"
  exit 0
fi

echo "Running preflight capacity checks in '$LOCATION'..."

print_region_help() {
  cat <<EOF

${BOLD}How to change regions:${NC}
  1. Tear down current deployment (if any):
       azd down --force --purge
  2. Set a new region:
       azd env set AZURE_LOCATION <region>     # e.g. eastus, canadaeast, japaneast
       # Optionally pin Azure OpenAI separately:
       azd env set AZURE_OPENAI_LOCATION <region>
  3. Re-run:
       azd up

${BOLD}Regions validated to support ALL required services${NC}
${BOLD}(Search basic + gpt-4o + text-embedding-3-small + APIM BasicV2):${NC}
  🇺🇸 eastus, eastus2
  🇨🇦 canadaeast
  🌏 japaneast, australiaeast

Other regions may have gpt-4o but lack text-embedding-3-small
(e.g. westus3, southcentralus, swedencentral, uksouth) and will fail mid-deploy.
EOF
}

# --- Azure AI Search quota check ---
echo -n "  • Azure AI Search (basic SKU) quota... "
SEARCH_USAGE_JSON=$(az rest --method get \
  --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Search/locations/${LOCATION}/usages?api-version=2023-11-01" \
  2>/dev/null || echo "")

if [ -z "$SEARCH_USAGE_JSON" ]; then
  echo -e "${YELLOW}SKIPPED (could not query usages API)${NC}"
else
  BASIC_LIMIT=$(echo "$SEARCH_USAGE_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for v in d.get('value', []):
        if v.get('name', {}).get('value', '').lower() == 'basic':
            print(f\"{v.get('currentValue', 0)}/{v.get('limit', 0)}\")
            sys.exit(0)
    print('unknown')
except Exception:
    print('unknown')
" 2>/dev/null)

  if [ "$BASIC_LIMIT" = "unknown" ] || [ -z "$BASIC_LIMIT" ]; then
    echo -e "${YELLOW}SKIPPED (no basic SKU quota reported)${NC}"
  else
    CURRENT="${BASIC_LIMIT%/*}"
    LIMIT="${BASIC_LIMIT#*/}"
    if [ "$LIMIT" -gt 0 ] && [ "$CURRENT" -lt "$LIMIT" ]; then
      echo -e "${GREEN}OK${NC} (${CURRENT}/${LIMIT} used)"
    else
      echo -e "${RED}FAIL${NC} (${CURRENT}/${LIMIT} used)"
      echo -e "${RED}    Azure AI Search basic SKU is at quota limit in '${LOCATION}'.${NC}"
      FAIL=1
    fi
  fi
fi

# --- Azure OpenAI gpt-4o capacity check ---
echo -n "  • Azure OpenAI gpt-4o capacity in '${OPENAI_LOCATION}'... "
OPENAI_USAGE_JSON=$(az rest --method get \
  --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.CognitiveServices/locations/${OPENAI_LOCATION}/usages?api-version=2024-10-01" \
  2>/dev/null || echo "")

if [ -z "$OPENAI_USAGE_JSON" ]; then
  echo -e "${YELLOW}SKIPPED (could not query Cognitive Services usages)${NC}"
else
  GPT4O_AVAIL=$(echo "$OPENAI_USAGE_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for v in d.get('value', []):
        name = v.get('name', {}).get('value', '')
        # Match standard (non-regional/non-global) gpt-4o quota
        if name == 'OpenAI.Standard.gpt-4o':
            cur = v.get('currentValue', 0)
            lim = v.get('limit', 0)
            print(f\"{lim-cur}|{cur}|{lim}\")
            sys.exit(0)
    print('unknown')
except Exception:
    print('unknown')
" 2>/dev/null)

  if [ "$GPT4O_AVAIL" = "unknown" ] || [ -z "$GPT4O_AVAIL" ]; then
    echo -e "${YELLOW}SKIPPED (no gpt-4o Standard quota reported in region)${NC}"
    echo -e "${YELLOW}    Note: gpt-4o may not be available in '${OPENAI_LOCATION}'.${NC}"
  else
    AVAIL="${GPT4O_AVAIL%%|*}"
    REST="${GPT4O_AVAIL#*|}"
    CUR="${REST%%|*}"
    LIM="${REST#*|}"
    # Convert floats to ints for comparison
    AVAIL_INT=$(printf '%.0f' "$AVAIL")
    if [ "$AVAIL_INT" -ge "$REQUIRED_GPT4O_CAPACITY" ]; then
      echo -e "${GREEN}OK${NC} (${AVAIL}K TPM available, need ${REQUIRED_GPT4O_CAPACITY}K)"
    else
      echo -e "${RED}FAIL${NC} (${AVAIL}K TPM available, need ${REQUIRED_GPT4O_CAPACITY}K; ${CUR}/${LIM} used)"
      echo -e "${RED}    Insufficient gpt-4o Standard quota in '${OPENAI_LOCATION}'.${NC}"
      FAIL=1
    fi
  fi
fi

echo ""

if [ "$FAIL" -eq 1 ]; then
  echo -e "${RED}${BOLD}❌ Preflight check failed: insufficient regional capacity/quota.${NC}"
  print_region_help
  echo ""
  echo -e "${YELLOW}To bypass this check (e.g., for retry after transient capacity issue):${NC}"
  echo "  azd env set SKIP_PREFLIGHT true"
  exit 1
fi

echo -e "${GREEN}✅ Preflight checks passed.${NC}"
exit 0
