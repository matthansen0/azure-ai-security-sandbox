# Lab 2: API Management AI Gateway

**Objective:** Verify that Azure API Management is acting as an AI Gateway between the application and Azure OpenAI. Understand managed identity authentication, retry policies, and how to inspect gateway traffic.

**Time:** ~25 minutes

**Requires:** Deployment with `useAPIM=true` (default)

---

## Setup

```bash
# Load environment variables
eval "$(azd env get-values | sed 's/^/export /')"

# Get APIM service name
APIM_NAME=$(az apim list -g "rg-${AZURE_ENV_NAME}" --query "[0].name" -o tsv)
echo "APIM Service: $APIM_NAME"

# Get APIM gateway URL
APIM_URL="https://${APIM_NAME}.azure-api.net"
echo "APIM Gateway: $APIM_URL"

# Get APIM subscription key for testing
APIM_KEY=$(az apim subscription keys list \
  -g "rg-${AZURE_ENV_NAME}" \
  --service-name "$APIM_NAME" \
  --subscription-id internal-apps \
  --query primaryKey -o tsv)
echo "Subscription key retrieved: $([ -n "$APIM_KEY" ] && echo 'yes' || echo 'no')"
```

---

## Exercise 1: Verify APIM Is Proxying to Azure OpenAI

Send a request directly to APIM to confirm it can reach Azure OpenAI using managed identity.

```bash
# Test the Azure-style endpoint (deployment name in URL)
curl -sS -X POST "${APIM_URL}/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
  -H "api-key: ${APIM_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Say hello in exactly 3 words."}],
    "max_tokens": 20
  }' | jq '{model: .model, response: .choices[0].message.content, usage: .usage}'
```

**What to look for:**
- A valid response from GPT-4o (not an error)
- The `usage` field showing `prompt_tokens` and `completion_tokens`
- No API key was sent to Azure OpenAI — APIM used its **managed identity**

---

## Exercise 2: Verify the OpenAI SDK URL Rewrite

The upstream application uses the OpenAI SDK format (`/chat/completions` with `model` in the body). APIM rewrites this to Azure OpenAI format (`/deployments/{model}/chat/completions`).

```bash
# Test the OpenAI SDK-style endpoint (model in body, not URL)
curl -sS -X POST "${APIM_URL}/openai/v1/chat/completions" \
  -H "api-key: ${APIM_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "What is 2+2? Answer with just the number."}],
    "max_tokens": 10
  }' | jq '{model: .model, response: .choices[0].message.content}'
```

**What to look for:**
- Same successful response as Exercise 1
- APIM extracted `model` from the request body and rewrote the URL to `/deployments/gpt-4o/chat/completions`

---

## Exercise 3: Inspect APIM's Managed Identity

Verify that APIM authenticates to Azure OpenAI with managed identity, not an API key.

```bash
# Check APIM identity
az apim show -g "rg-${AZURE_ENV_NAME}" -n "$APIM_NAME" \
  --query "{identity_type: identity.type, principal_id: identity.principalId}" -o json

# Check role assignment: APIM → Azure OpenAI
APIM_PRINCIPAL=$(az apim show -g "rg-${AZURE_ENV_NAME}" -n "$APIM_NAME" \
  --query "identity.principalId" -o tsv)

OPENAI_NAME=$(az cognitiveservices account list -g "rg-${AZURE_ENV_NAME}" \
  --query "[0].name" -o tsv)

az role assignment list \
  --assignee "$APIM_PRINCIPAL" \
  --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-${AZURE_ENV_NAME}/providers/Microsoft.CognitiveServices/accounts/${OPENAI_NAME}" \
  --query "[].{role: roleDefinitionName, scope: scope}" -o table
```

**What to look for:**
- Identity type: `SystemAssigned`
- Role assignment: `Cognitive Services OpenAI Contributor` (or `Cognitive Services OpenAI User`)
- This proves APIM uses its own identity to call Azure OpenAI — no shared API key

---

## Exercise 4: Inspect APIM Policies

Look at the policies that control how APIM handles requests.

```bash
# List APIs configured in APIM
az apim api list -g "rg-${AZURE_ENV_NAME}" \
  --service-name "$APIM_NAME" \
  --query "[].{name: name, path: path, displayName: displayName}" -o table

# Get the all-operations policy (base/global for the OpenAI API)
az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-${AZURE_ENV_NAME}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/apis/openai/policies/policy?api-version=2023-09-01-preview&format=rawxml" \
  --query "properties.value" -o tsv 2>/dev/null || echo "(Use Azure Portal to view policies if CLI fails)"
```

**Key policies to look for in the output:**
- `<authentication-managed-identity resource="https://cognitiveservices.azure.com" />` — Managed identity auth
- `<retry>` — Retry logic for 429 (rate limit) and 5xx errors
- `<set-header name="api-key" exists-action="delete">` — Strips the incoming subscription key before forwarding
- `<set-backend-service>` — Routes to the Azure OpenAI backend

---

## Exercise 5: Test Retry Behavior

APIM retries requests when Azure OpenAI returns 429 (rate limit). While hard to trigger on demand, you can verify the policy is configured.

```bash
# Send several rapid requests to see rate limit headers
for i in {1..5}; do
  echo "--- Request $i ---"
  curl -sS -o /dev/null -w "Status: %{http_code}\n" \
    -D - \
    -X POST "${APIM_URL}/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
    -H "api-key: ${APIM_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":5}' 2>&1 | grep -iE "^(Status|x-ratelimit|retry-after|x-ms)"
  echo ""
done
```

**What to look for:**
- `x-ratelimit-remaining-*` headers from Azure OpenAI (forwarded through APIM)
- If you send enough requests fast enough, you may see a 429 which APIM retries automatically
- The user sees the final response (success or failure after retries), not intermediate 429s

---

## Exercise 6: View APIM Gateway Logs

Check what APIM logged for your test requests.

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace list -g "rg-${AZURE_ENV_NAME}" \
  --query "[0].customerId" -o tsv)
TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)

QUERY="AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.APIMANAGEMENT'
| where Category == 'GatewayLogs'
| project TimeGenerated, 
    method=requestMethod_s, 
    url=url_s,
    status=responseCode_d,
    duration=totalTime_d,
    clientIP=callerIpAddress_s,
    backend=backendUrl_s,
    backendStatus=backendResponseCode_d
| order by TimeGenerated desc
| take 10"

curl -sS -X POST "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -nc --arg q "$QUERY" '{query:$q}')" | jq '.tables[0] | {columns: [.columns[].name], rows: .rows[:5]}'
```

**What to look for:**
- `backendUrl`: Points to your Azure OpenAI endpoint
- `status` vs `backendStatus`: APIM's response vs the backend's response (usually both 200)
- `duration`: Total time including APIM processing + backend call
- `clientIP`: Your IP address (or the Container App's IP)

---

## Exercise 7: Compare Direct vs APIM-Proxied Access

Understand the security difference between direct and proxied access.

```bash
# Through APIM (uses subscription key → APIM → managed identity → OpenAI)
echo "=== Through APIM ==="
curl -sS -X POST "${APIM_URL}/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
  -H "api-key: ${APIM_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' | jq .choices[0].message.content

# Without subscription key (should fail)
echo ""
echo "=== Without subscription key ==="
curl -sS -X POST "${APIM_URL}/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' | jq .
```

**What to look for:**
- First request succeeds (valid subscription key)
- Second request fails with HTTP 401 — APIM requires authentication
- This proves APIM controls access to Azure OpenAI

---

## What You Learned

- APIM sits between the app and Azure OpenAI, acting as a security gateway
- APIM authenticates to Azure OpenAI using **managed identity**, not API keys
- The app authenticates to APIM using a **subscription key**
- APIM rewrites OpenAI SDK-style URLs to Azure OpenAI format
- Retry policies handle rate limits (429s) automatically
- All gateway traffic is logged and queryable in Log Analytics

## Next Lab

Continue to [Lab 3: Managed Identity & RBAC](lab-3-managed-identity-rbac.md) to explore the zero-secrets identity architecture.
