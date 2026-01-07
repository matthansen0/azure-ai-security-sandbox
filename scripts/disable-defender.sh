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
if [[ "$CHANGES_COUNT" == "0" ]]; then
  echo "No recorded pricing changes in $STATE_FILE. Nothing to do."
  exit 0
fi

echo "Rolling back $CHANGES_COUNT Defender plan changes in subscription: $SUBSCRIPTION_ID"

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
  az security pricing create --name "$PLAN_NAME" --tier "$PREV_TIER" --output none
 done

echo "Rollback complete. State file retained at: $STATE_FILE"
