#!/usr/bin/env bash

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT

cat > "$TEST_BIN/az" <<'MOCK_AZ'
#!/usr/bin/env bash

set -eu

if [ "$1" = "rest" ]; then
  case "$*" in
    *Microsoft.Search*)
      printf '%s\n' '{"value":[{"name":{"value":"basic"},"currentValue":0,"limit":12}]}'
      ;;
    *Microsoft.CognitiveServices*)
      if [ "${PREFLIGHT_SCENARIO:-success}" = "success" ]; then
        printf '%s\n' '{"value":[{"name":{"value":"OpenAI.Standard.gpt-4o"},"currentValue":0,"limit":150},{"name":{"value":"OpenAI.Standard.text-embedding-3-small"},"currentValue":0,"limit":350}]}'
      else
        printf '%s\n' '{"value":[{"name":{"value":"OpenAI.Standard.gpt-4o"},"currentValue":0,"limit":150}]}'
      fi
      ;;
  esac
elif [ "$1" = "cognitiveservices" ] && [ "$2" = "model" ] && [ "$3" = "list" ]; then
  case "${PREFLIGHT_SCENARIO:-success}" in
    success)
      printf '%s\n' '[{"model":{"name":"gpt-4o","version":"2024-11-20","skus":[{"name":"Standard"}]}},{"model":{"name":"text-embedding-3-small","version":"1","skus":[{"name":"Standard"}]}}]'
      ;;
    missing-embedding)
      printf '%s\n' '[{"model":{"name":"gpt-4o","version":"2024-11-20","skus":[{"name":"Standard"}]}},{"model":{"name":"text-embedding-3-small","version":"1","skus":[{"name":"GlobalStandard"}]}}]'
      ;;
    unavailable-catalog)
      exit 1
      ;;
  esac
else
  printf 'Unexpected az invocation: %s\n' "$*" >&2
  exit 2
fi
MOCK_AZ
chmod +x "$TEST_BIN/az"

run_preflight() {
  PREFLIGHT_SCENARIO="$1" \
    PATH="$TEST_BIN:$PATH" \
    AZURE_LOCATION="test-region" \
    AZURE_OPENAI_LOCATION="test-region" \
    AZURE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" \
    "$REPO_ROOT/scripts/preflight-check.sh" >/dev/null 2>&1
}

run_preflight success

if run_preflight missing-embedding; then
  echo "Expected a missing Standard embedding SKU to fail preflight." >&2
  exit 1
fi

if run_preflight unavailable-catalog; then
  echo "Expected an unreadable model catalog to fail preflight." >&2
  exit 1
fi

echo "Preflight regression tests passed."