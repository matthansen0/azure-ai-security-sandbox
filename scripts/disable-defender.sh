#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Disable (roll back) subscription-wide Microsoft Defender for Cloud plans that were enabled
by ./scripts/enable-defender.sh.

WARNING: This changes subscription-wide Defender settings.

Usage:
  ./scripts/disable-defender.sh --confirm

Notes:
- Requires: azd, az (logged in), jq
- Requires: a state file created by enable-defender.sh
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
  echo "Refusing to change subscription-wide Defender plans without --confirm." >&2
  usage
  exit 2
fi

for bin in azd az jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "$bin not found on PATH" >&2
    exit 1
  fi
done

SUBSCRIPTION_ID="$(azd env get-value AZURE_SUBSCRIPTION_ID 2>/dev/null || true)"
ENV_NAME="$(azd env get-value AZURE_ENV_NAME 2>/dev/null || true)"

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "Missing AZURE_SUBSCRIPTION_ID in azd env. Run azd up/provision first." >&2
  exit 1
fi

STATE_DIR=".defender"
STATE_FILE="$STATE_DIR/defender-state-${ENV_NAME:-sandbox}.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "State file not found: $STATE_FILE" >&2
  echo "Nothing to roll back (or enable-defender.sh hasn't been run)." >&2
  exit 1
fi

az account set --subscription "$SUBSCRIPTION_ID" >/dev/null

CHANGES_COUNT="$(jq '.pricingChanges | length' "$STATE_FILE")"
ALREADY_ENABLED_COUNT="$(jq '.alreadyEnabled // [] | length' "$STATE_FILE")"

# Report plans that were already enabled (we won't touch these)
if [[ "$ALREADY_ENABLED_COUNT" -gt 0 ]]; then
  echo "Plans that were already enabled before this sandbox (not rolling back):"
  jq -r '.alreadyEnabled // [] | .[]' "$STATE_FILE" | while read -r plan; do
    echo "  - $plan (was already Standard)"
  done
  echo ""
fi

if [[ "$CHANGES_COUNT" == "0" ]]; then
  echo "No pricing changes were made by enable-defender.sh. Nothing to roll back."
  exit 0
fi

echo "Rolling back $CHANGES_COUNT Defender plan changes in subscription: $SUBSCRIPTION_ID"

# Enable/disable a Defender plan using ARM REST (fallback from broken `az security pricing create`)
set_defender_plan_tier() {
  local plan_name="$1"
  local tier="$2"
  local base_uri="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/${plan_name}"
  local body
  body="$(jq -n --arg tier "$tier" '{properties:{pricingTier:$tier}}')"

  # Try CLI first (may work in some environments)
  if az security pricing create --name "$plan_name" --tier "$tier" --output none 2>/dev/null; then
    return 0
  fi

  echo "  (using az rest fallback)" >&2
  local api_version
  for api_version in 2023-01-01 2022-03-01; do
    if az rest --method put \
         --uri "${base_uri}?api-version=${api_version}" \
         --body "$body" \
         --output none 2>/dev/null; then
      return 0
    fi
  done

  echo "ERROR: Failed to set Defender plan '$plan_name' to '$tier' via CLI and REST." >&2
  return 1
}

jq -c '.pricingChanges[]' "$STATE_FILE" | while read -r change; do
  PLAN_NAME="$(jq -r '.name' <<<"$change")"
  PREV_TIER="$(jq -r '.previousTier' <<<"$change")"

  if [[ -z "$PLAN_NAME" || "$PLAN_NAME" == "null" ]]; then
    continue
  fi

  # Fall back to Free if the previous tier is unknown.
  if [[ -z "$PREV_TIER" || "$PREV_TIER" == "null" ]]; then
    PREV_TIER="Free"
  fi

  echo "- Setting $PLAN_NAME tier back to $PREV_TIER"
  set_defender_plan_tier "$PLAN_NAME" "$PREV_TIER" || echo "  WARNING: Could not revert $PLAN_NAME" >&2
 done

echo "Rollback complete. State file retained at: $STATE_FILE"
