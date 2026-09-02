#!/usr/bin/env bash
# preflight-check.sh
# Checks regional quota for Azure AI Search and the exact Azure OpenAI models
# before attempting a full deployment. Emits actionable errors + region-change
# instructions when a model, SKU, or quota is unavailable.
#
# Exits 0 on success, 1 on quota/capacity issue.

set -u

LOCATION="${AZURE_LOCATION:-}"
OPENAI_LOCATION="${AZURE_OPENAI_LOCATION:-$LOCATION}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null)}"

# These values must match infra/modules/ai-services.bicep.
CHAT_MODEL_NAME="gpt-4o"
CHAT_MODEL_VERSION="2024-11-20"
EMBEDDING_MODEL_NAME="text-embedding-3-small"
EMBEDDING_MODEL_VERSION="1"
MODEL_SKU="Standard"
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

# --- Azure OpenAI model and SKU availability ---
echo "  • Azure OpenAI model availability in '${OPENAI_LOCATION}':"
MODEL_CATALOG_JSON=$(az cognitiveservices model list \
  --location "$OPENAI_LOCATION" \
  --subscription "$SUBSCRIPTION_ID" \
  -o json 2>/dev/null || echo "")

check_model_sku() {
  MODEL_NAME="$1"
  MODEL_VERSION="$2"
  echo -n "    - ${MODEL_NAME} ${MODEL_VERSION} (${MODEL_SKU})... "

  MODEL_SUPPORTED=$(printf '%s' "$MODEL_CATALOG_JSON" | python3 -c '
import json
import sys

model_name, model_version, sku_name = sys.argv[1:]
try:
    models = json.load(sys.stdin)
    supported = any(
        item.get("model", {}).get("name") == model_name
        and item.get("model", {}).get("version") == model_version
        and sku_name in [sku.get("name") for sku in item.get("model", {}).get("skus", [])]
        for item in models
    )
    print("true" if supported else "false")
except Exception:
    print("unknown")
' "$MODEL_NAME" "$MODEL_VERSION" "$MODEL_SKU" 2>/dev/null)

  if [ "$MODEL_SUPPORTED" = "true" ]; then
    echo -e "${GREEN}OK${NC}"
  elif [ "$MODEL_SUPPORTED" = "false" ]; then
    echo -e "${RED}FAIL${NC}"
    echo -e "${RED}      Required model version or SKU is unavailable in '${OPENAI_LOCATION}'.${NC}"
    FAIL=1
  else
    echo -e "${RED}FAIL (could not parse model catalog)${NC}"
    FAIL=1
  fi
}

if [ -z "$MODEL_CATALOG_JSON" ]; then
  echo -e "${RED}    FAIL (could not query model catalog)${NC}"
  FAIL=1
else
  check_model_sku "$CHAT_MODEL_NAME" "$CHAT_MODEL_VERSION"
  check_model_sku "$EMBEDDING_MODEL_NAME" "$EMBEDDING_MODEL_VERSION"
fi

# --- Azure OpenAI capacity checks ---
OPENAI_USAGE_JSON=$(az rest --method get \
  --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.CognitiveServices/locations/${OPENAI_LOCATION}/usages?api-version=2024-10-01" \
  2>/dev/null || echo "")

check_openai_capacity() {
  MODEL_NAME="$1"
  REQUIRED_CAPACITY="$2"
  QUOTA_NAME="OpenAI.${MODEL_SKU}.${MODEL_NAME}"
  echo -n "  • Azure OpenAI ${MODEL_NAME} capacity in '${OPENAI_LOCATION}'... "

  CAPACITY=$(printf '%s' "$OPENAI_USAGE_JSON" | python3 -c '
import json
import sys

quota_name = sys.argv[1]
try:
    usages = json.load(sys.stdin).get("value", [])
    quota = next(
        (item for item in usages if item.get("name", {}).get("value") == quota_name),
        None,
    )
    if quota is None:
        print("unknown")
    else:
        current = quota.get("currentValue", 0)
        limit = quota.get("limit", 0)
        print(f"{limit - current}|{current}|{limit}")
except Exception:
    print("unknown")
' "$QUOTA_NAME" 2>/dev/null)

  if [ "$CAPACITY" = "unknown" ] || [ -z "$CAPACITY" ]; then
    echo -e "${RED}FAIL (no ${MODEL_SKU} quota reported)${NC}"
    FAIL=1
  else
    AVAIL="${CAPACITY%%|*}"
    REST="${CAPACITY#*|}"
    CUR="${REST%%|*}"
    LIM="${REST#*|}"
    AVAIL_INT=$(printf '%.0f' "$AVAIL")
    if [ "$AVAIL_INT" -ge "$REQUIRED_CAPACITY" ]; then
      echo -e "${GREEN}OK${NC} (${AVAIL}K TPM available, need ${REQUIRED_CAPACITY}K)"
    else
      echo -e "${RED}FAIL${NC} (${AVAIL}K TPM available, need ${REQUIRED_CAPACITY}K; ${CUR}/${LIM} used)"
      echo -e "${RED}    Insufficient ${MODEL_NAME} ${MODEL_SKU} quota in '${OPENAI_LOCATION}'.${NC}"
      FAIL=1
    fi
  fi
}

if [ -z "$OPENAI_USAGE_JSON" ]; then
  echo -e "${RED}  • Azure OpenAI capacity... FAIL (could not query Cognitive Services usages)${NC}"
  FAIL=1
else
  check_openai_capacity "$CHAT_MODEL_NAME" "$REQUIRED_GPT4O_CAPACITY"
  check_openai_capacity "$EMBEDDING_MODEL_NAME" "$REQUIRED_EMBEDDING_CAPACITY"
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
