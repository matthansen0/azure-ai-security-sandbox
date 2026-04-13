# Lab 1: WAF & Front Door

**Objective:** Verify that Azure Front Door and the Web Application Firewall (WAF) are protecting the application at the edge. Understand Detection vs Prevention modes and learn to read WAF logs.

**Time:** ~20 minutes

**Requires:** Full deployment with `useAFD=true` (default)

---

## Setup

```bash
# Load environment variables
eval "$(azd env get-values | sed 's/^/export /')"

# Get the Front Door endpoint
AFD_ENDPOINT=$(azd env get-value APP_PUBLIC_URL)
echo "Front Door URL: $AFD_ENDPOINT"

# Get the Container App FQDN (direct, bypasses AFD)
CONTAINER_APP_FQDN=$(az containerapp show \
  -n "ca-${AZURE_ENV_NAME}" \
  -g "rg-${AZURE_ENV_NAME}" \
  --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || \
  az containerapp list -g "rg-${AZURE_ENV_NAME}" --query "[0].properties.configuration.ingress.fqdn" -o tsv)
echo "Container App URL: https://$CONTAINER_APP_FQDN"
```

---

## Exercise 1: Verify Front Door Is Routing Traffic

Send a request through Front Door and confirm it reaches your application.

```bash
# Request through Front Door
curl -sS -o /dev/null -w "Status: %{http_code}\nHeaders:\n" -D - \
  "${AFD_ENDPOINT}" 2>&1 | head -20
```

**What to look for:**
- HTTP 200 response
- `x-azure-ref` header — this confirms the request went through Azure Front Door
- `x-fd-healthprobe` should NOT be present (that's only for health probes)

Now compare with a direct request to the Container App:

```bash
# Direct to Container App (bypasses Front Door)
curl -sS -o /dev/null -w "Status: %{http_code}\n" \
  "https://$CONTAINER_APP_FQDN"
```

**Key takeaway:** Both URLs serve the same app. Front Door adds caching, WAF, and global edge presence.

---

## Exercise 2: Inspect the WAF Policy Configuration

Check what WAF rules are active and what mode they're in.

```bash
# Find the WAF policy name
WAF_NAME=$(az network front-door waf-policy list \
  -g "rg-${AZURE_ENV_NAME}" \
  --query "[0].name" -o tsv 2>/dev/null || \
  az resource list -g "rg-${AZURE_ENV_NAME}" \
    --resource-type "Microsoft.Network/FrontDoorWebApplicationFirewallPolicies" \
    --query "[0].name" -o tsv)
echo "WAF Policy: $WAF_NAME"

# Check WAF mode and managed rule sets
az network front-door waf-policy show \
  -g "rg-${AZURE_ENV_NAME}" \
  -n "$WAF_NAME" \
  --query "{mode: policySettings.mode, enabled: policySettings.enabledState, ruleSets: managedRules.managedRuleSets[].{type: ruleSetType, version: ruleSetVersion}}" \
  -o json 2>/dev/null || \
  az rest --method get \
    --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-${AZURE_ENV_NAME}/providers/Microsoft.Network/FrontDoorWebApplicationFirewallPolicies/${WAF_NAME}?api-version=2024-02-01" \
    --query "{mode: properties.policySettings.mode, enabled: properties.policySettings.enabledState, ruleSets: properties.managedRules.managedRuleSets[].{type: ruleSetType, version: ruleSetVersion}}" -o json
```

**What to look for:**
- `mode: Detection` — WAF is logging but not blocking
- `Microsoft_DefaultRuleSet 2.1` — OWASP Core Rule Set (CRS) covering SQL injection, XSS, etc.
- `Microsoft_BotManagerRuleSet 1.1` — Bot detection rules

---

## Exercise 3: Trigger WAF Rules (Detection Mode)

Send requests that would normally be caught by WAF rules. In Detection mode, they'll be **logged but not blocked**.

### 3a. SQL Injection Attempt

```bash
curl -sS -o /dev/null -w "Status: %{http_code}\n" \
  "${AFD_ENDPOINT}/?id=1%20OR%201=1--"
```

### 3b. Cross-Site Scripting (XSS) Attempt

```bash
curl -sS -o /dev/null -w "Status: %{http_code}\n" \
  "${AFD_ENDPOINT}/?q=<script>alert('xss')</script>"
```

### 3c. Path Traversal Attempt

```bash
curl -sS -o /dev/null -w "Status: %{http_code}\n" \
  "${AFD_ENDPOINT}/../../etc/passwd"
```

**Expected result in Detection mode:** All requests return HTTP 200 (or 3xx redirect). WAF logs the violations but does not block them.

> **Note:** If WAF were in Prevention mode, these requests would return HTTP 403.

---

## Exercise 4: Query WAF Logs in Log Analytics

After a few minutes (log ingestion delay), query Log Analytics to see the WAF detections.

```bash
# Get the Log Analytics workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  -g "rg-${AZURE_ENV_NAME}" \
  -n "$(az monitor log-analytics workspace list -g "rg-${AZURE_ENV_NAME}" --query "[0].name" -o tsv)" \
  --query customerId -o tsv)

TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)

# Query WAF logs for recent detections
QUERY="AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.CDN' or ResourceProvider == 'MICROSOFT.NETWORK'
| where Category == 'FrontDoorWebApplicationFirewallLog' or Category == 'FrontdoorWebApplicationFirewallLog'
| project TimeGenerated, action_s, ruleName_s, host_s, requestUri_s, details_msg_s, policyMode_s
| order by TimeGenerated desc
| take 20"

curl -sS -X POST "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -nc --arg q "$QUERY" '{query:$q}')" | jq '.tables[0] | {columns: [.columns[].name], rows: .rows[:5]}'
```

**What to look for:**
- `action_s`: `Detection` (logged, not blocked)
- `ruleName_s`: The specific OWASP rule that matched (e.g., `SQL Injection`, `XSS`)
- `requestUri_s`: The URL that triggered the rule
- `policyMode_s`: Should show `detection`

---

## Exercise 5: Understand Detection vs Prevention

Compare what happens when WAF is in each mode.

### Current Behavior (Detection)

| Malicious Request | HTTP Response | WAF Log Entry |
|---|---|---|
| SQL injection in URL | 200 (passes through) | `action: Detection` |
| XSS in query param | 200 (passes through) | `action: Detection` |
| Path traversal | 200 (passes through) | `action: Detection` |

### What Prevention Mode Would Do

| Malicious Request | HTTP Response | WAF Log Entry |
|---|---|---|
| SQL injection in URL | **403 (blocked)** | `action: Block` |
| XSS in query param | **403 (blocked)** | `action: Block` |
| Path traversal | **403 (blocked)** | `action: Block` |

> **Why not default to Prevention?** WAF rules can generate false positives. JSON API payloads sometimes trigger SQL injection rules. Detection mode lets you identify false positives before accidentally blocking legitimate traffic.

### Optional: Switch to Prevention Mode

If you want to test Prevention mode (requests will be blocked):

```bash
# Switch WAF to Prevention mode
az rest --method patch \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-${AZURE_ENV_NAME}/providers/Microsoft.Network/FrontDoorWebApplicationFirewallPolicies/${WAF_NAME}?api-version=2024-02-01" \
  --body '{"properties": {"policySettings": {"mode": "Prevention"}}}'

# Wait a few minutes for propagation, then retry the SQL injection test
curl -sS -o /dev/null -w "Status: %{http_code}\n" \
  "${AFD_ENDPOINT}/?id=1%20OR%201=1--"
# Expected: HTTP 403
```

> **Remember to switch back to Detection mode when done:**
> ```bash
> az rest --method patch \
>   --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-${AZURE_ENV_NAME}/providers/Microsoft.Network/FrontDoorWebApplicationFirewallPolicies/${WAF_NAME}?api-version=2024-02-01" \
>   --body '{"properties": {"policySettings": {"mode": "Detection"}}}'
> ```

---

## What You Learned

- Front Door adds the `x-azure-ref` header to all proxied requests
- WAF in Detection mode logs threats without blocking them
- Both OWASP and Bot Manager rule sets are active
- WAF logs appear in Log Analytics under `FrontDoorWebApplicationFirewallLog`
- Switching between Detection and Prevention mode is a single property change

## Next Lab

Continue to [Lab 2: API Management AI Gateway](lab-2-api-management-gateway.md) to explore the AI Gateway layer.
