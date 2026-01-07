#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Enable subscription-wide Microsoft Defender for Cloud plans used by this sandbox.

WARNING: This is subscription-scoped enablement (billing + coverage).
Run this only in a dedicated subscription for the sandbox, or be comfortable
that it will apply to the whole subscription.

Usage:
  ./scripts/enable-defender.sh --confirm

Notes:
- Requires: azd, az (logged in)
- Requires: you already ran `azd up` (or at least `azd provision`) so the azd env exists.
- Lists available Defender plans via `az rest` (ARM) with fallback to `az security pricing list`.
- Creates a local state file under `.defender/` so you can roll back later with:
  `./scripts/disable-defender.sh --confirm`

Discover plan names in your subscription:
  az rest --method get --uri "https://management.azure.com/subscriptions/<subId>/providers/Microsoft.Security/pricings?api-version=2023-01-01" | jq
EOF
}

CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRM=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$CONFIRM" != "true" ]]; then
  echo "Refusing to enable subscription-wide Defender plans without --confirm." >&2
  usage
  exit 2
fi

if ! command -v azd >/dev/null 2>&1; then
  echo "azd not found on PATH" >&2
  exit 1
fi

if ! command -v az >/dev/null 2>&1; then
  echo "az (Azure CLI) not found on PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found on PATH (required for state tracking)" >&2
  exit 1
fi

SUBSCRIPTION_ID="$(azd env get-value AZURE_SUBSCRIPTION_ID 2>/dev/null || true)"
LOCATION="$(azd env get-value AZURE_LOCATION 2>/dev/null || true)"
ENV_NAME="$(azd env get-value AZURE_ENV_NAME 2>/dev/null || true)"
RESOURCE_GROUP_NAME="$(azd env get-value RESOURCE_GROUP_NAME 2>/dev/null || true)"
STORAGE_ACCOUNT_NAME="$(azd env get-value AZURE_STORAGE_ACCOUNT 2>/dev/null || true)"
AI_GATEWAY_ENABLED="$(azd env get-value AI_GATEWAY_ENABLED 2>/dev/null || true)"
APIM_SERVICE_NAME="$(azd env get-value APIM_SERVICE_NAME 2>/dev/null || true)"

if [[ -z "$SUBSCRIPTION_ID" || -z "$LOCATION" ]]; then
  echo "Missing AZURE_SUBSCRIPTION_ID/AZURE_LOCATION in azd env." >&2
  echo "Run: azd up (or azd provision) first." >&2
  exit 1
fi

az account set --subscription "$SUBSCRIPTION_ID" >/dev/null

DEPLOYMENT_NAME="defender-addon-${ENV_NAME:-sandbox}-$(date +%Y%m%d%H%M%S)"
STORAGE_TEMPLATE_FILE="infra/addons/defender/storage-settings.bicep"

STATE_DIR=".defender"
STATE_FILE="$STATE_DIR/defender-state-${ENV_NAME:-sandbox}.json"

mkdir -p "$STATE_DIR"

echo "Validating available Defender plans in subscription: $SUBSCRIPTION_ID"

get_defender_pricings_json() {
  # Azure CLI's `az security pricing list` has intermittently broken due to SDK signature
  # changes (e.g., PricingsOperations.list now requiring scope_id). Use ARM REST as the
  # stable source of truth, with a best-effort fallback to the CLI command.
  local pricing_json
  if pricing_json="$(az security pricing list -o json 2>/dev/null)"; then
    echo "$pricing_json"
    return 0
  fi

  echo "WARN: 'az security pricing list' failed; using 'az rest' to list Defender pricings." >&2

  local base_uri="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings"
  local api_version
  local rest_json
  for api_version in 2023-01-01 2022-03-01 2021-07-01-preview; do
    if rest_json="$(az rest --method get --uri "${base_uri}?api-version=${api_version}" -o json 2>/dev/null)"; then
      # Normalize to the same shape as `az security pricing list`: a JSON array of pricings.
      jq -c '.value // []' <<<"$rest_json"
      return 0
    fi
  done

  echo "ERROR: Unable to list Defender pricings via Azure CLI or ARM REST." >&2
  echo "- Verify you're logged in: az login" >&2
  echo "- Verify subscription access: az account show" >&2
  return 1
}

PRICING_JSON="$(get_defender_pricings_json)"
AVAILABLE_PLANS_JSON="$(jq -c '[.[].name]' <<<"$PRICING_JSON")"

desired_plans=()

# Relevant to this sandbox deployment
desired_plans+=("Containers")

if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
  desired_plans+=("StorageAccounts")
fi

if [[ -n "$(azd env get-value AZURE_COSMOSDB_ENDPOINT 2>/dev/null || true)" ]]; then
  desired_plans+=("CosmosDbs")
fi

# Only relevant when APIM is deployed
if [[ "${AI_GATEWAY_ENABLED,,}" == "true" || -n "$APIM_SERVICE_NAME" ]]; then
  desired_plans+=("Api")
fi

echo "Desired Defender plan names (pre-validation): ${desired_plans[*]}"

plan_exists() {
  local plan="$1"
  jq -e --arg p "$plan" 'index($p) != null' <<<"$AVAILABLE_PLANS_JSON" >/dev/null
}

plan_tier() {
  local plan="$1"
  jq -r --arg p "$plan" '.[] | select(.name == $p) | .pricingTier // .properties.pricingTier // empty' <<<"$PRICING_JSON" | head -n1
}

# Enable a Defender plan using ARM REST (fallback from broken `az security pricing create`)
# Some plans (like Api) require a subPlan property.
enable_defender_plan() {
  local plan_name="$1"
  local tier="$2"
  local sub_plan="${3:-}"
  local base_uri="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/${plan_name}"
  local body

  if [[ -n "$sub_plan" ]]; then
    body="$(jq -n --arg tier "$tier" --arg subPlan "$sub_plan" '{properties:{pricingTier:$tier,subPlan:$subPlan}}')"
  else
    body="$(jq -n --arg tier "$tier" '{properties:{pricingTier:$tier}}')"
  fi

  # Try CLI first (may work in some environments)
  if [[ -n "$sub_plan" ]]; then
    if az security pricing create --name "$plan_name" --tier "$tier" --subplan "$sub_plan" --output none 2>/dev/null; then
      return 0
    fi
  else
    if az security pricing create --name "$plan_name" --tier "$tier" --output none 2>/dev/null; then
      return 0
    fi
  fi

  echo "  (using az rest fallback)" >&2
  local api_version
  for api_version in 2024-01-01 2023-01-01 2022-03-01; do
    if az rest --method put \
         --uri "${base_uri}?api-version=${api_version}" \
         --body "$body" \
         --output none 2>/dev/null; then
      return 0
    fi
  done

  echo "ERROR: Failed to enable Defender plan '$plan_name' via CLI and REST." >&2
  return 1
}

pricing_changes=()
already_enabled=()

echo "Enabling Defender plans (subscription-wide)"
for plan in "${desired_plans[@]}"; do
  if ! plan_exists "$plan"; then
    echo "- Skipping $plan (not available in this subscription)" >&2
    continue
  fi

  current_tier="$(plan_tier "$plan")"
  [[ -z "$current_tier" ]] && current_tier="Unknown"

  if [[ "$current_tier" == "Standard" ]]; then
    echo "- $plan already Standard (will not be changed by disable script)"
    already_enabled+=("$plan")
    continue
  fi

  # Determine sub-plan for plans that require it
  # Defender for APIs requires P1-P5; P1 is the smallest/cheapest tier
  sub_plan=""
  if [[ "$plan" == "Api" ]]; then
    sub_plan="P1"
  fi

  echo "- Setting $plan tier to Standard (was: $current_tier)${sub_plan:+ [subPlan: $sub_plan]}"
  if enable_defender_plan "$plan" "Standard" "$sub_plan"; then
    pricing_changes+=("$plan:$current_tier")
  else
    echo "  WARNING: Could not enable $plan" >&2
  fi
done

# Write state file for rollback
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg subscriptionId "$SUBSCRIPTION_ID" \
  --arg environment "$ENV_NAME" \
  --arg timestamp "$timestamp" \
  --argjson desiredPlans "$(printf '%s\n' "${desired_plans[@]}" | jq -R . | jq -s .)" \
  --argjson availablePlans "$AVAILABLE_PLANS_JSON" \
  --argjson alreadyEnabled "$(printf '%s\n' "${already_enabled[@]}" | jq -R . | jq -s .)" \
  --argjson pricingChanges "$(
      for entry in "${pricing_changes[@]}"; do
        name="${entry%%:*}"
        prev="${entry#*:}"
        jq -n --arg name "$name" --arg prev "$prev" --arg next "Standard" '{name:$name, previousTier:$prev, newTier:$next}'
      done | jq -s .
    )" \
  '{subscriptionId:$subscriptionId, environment:$environment, timestamp:$timestamp, desiredPlans:$desiredPlans, availablePlans:$availablePlans, alreadyEnabled:$alreadyEnabled, pricingChanges:$pricingChanges}' \
  > "$STATE_FILE"

echo "Wrote Defender enablement state: $STATE_FILE"

if [[ -n "$RESOURCE_GROUP_NAME" && -n "$STORAGE_ACCOUNT_NAME" ]]; then
  echo "Configuring Defender for Storage settings on account: $STORAGE_ACCOUNT_NAME (RG: $RESOURCE_GROUP_NAME)"
  az deployment group create \
    --name "${DEPLOYMENT_NAME}-storage" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "$STORAGE_TEMPLATE_FILE" \
    --parameters storageAccountName="$STORAGE_ACCOUNT_NAME" \
    --output table
else
  echo "Skipping storage settings add-on (missing RESOURCE_GROUP_NAME or AZURE_STORAGE_ACCOUNT in azd env)." >&2
fi

echo "Done. Verify in Defender for Cloud -> Environment settings -> $SUBSCRIPTION_ID."
