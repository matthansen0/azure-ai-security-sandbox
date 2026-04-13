# Lab 4: Monitoring & Log Analytics

**Objective:** Trace a request end-to-end through all security layers using Log Analytics and KQL queries. Learn to query diagnostic logs from Front Door, APIM, Container Apps, and Azure OpenAI.

**Time:** ~30 minutes

**Requires:** Base deployment (ideally with APIM and AFD enabled for full coverage)

---

## Exercise 1: Generate Traceable Traffic

Open the chat web app in your browser (the `APP_PUBLIC_URL` from the [prerequisites](README.md#prerequisites)) and ask a question that will exercise the full RAG pipeline. For example:

> **What is Northwind Health Plus?**

Ask 2-3 questions to generate enough traffic for the log queries below.

> **Note:** Wait 2-5 minutes for logs to appear in Log Analytics before proceeding.

---

## Exercise 2: Verify All Resources Send Diagnostic Logs

Set up the Log Analytics query helper, then check which resources are sending logs.

```bash
# Get Log Analytics workspace details
WORKSPACE_NAME=$(az monitor log-analytics workspace list -g "$RG" --query "[0].name" -o tsv)
WORKSPACE_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$WORKSPACE_NAME" \
  --query customerId -o tsv)
echo "Workspace: $WORKSPACE_NAME ($WORKSPACE_ID)"

# Get an access token for the Log Analytics API
TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)

# Helper function for running KQL queries (used throughout this lab)
run_query() {
  local query="$1"
  curl -sS -X POST "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg q "$query" '{query:$q}')" | jq '.tables[0]'
}

# Check what log tables have data
run_query "search * | distinct \$table | sort by \$table asc"
```

**What to look for:** Tables that should have data:
- `AzureDiagnostics` — Front Door WAF, APIM gateway logs
- `ContainerAppConsoleLogs_CL` or `ContainerAppSystemLogs_CL` — Container App logs
- `AppTraces`, `AppRequests`, `AppDependencies` — Application Insights telemetry

---

## Exercise 3: Trace a Request Through Front Door

See how Front Door handled your request.

```bash
run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.CDN'
| where Category == 'FrontDoorAccessLog'
| project TimeGenerated, 
    httpMethod_s, 
    requestUri_s, 
    httpStatusCode_d, 
    timeTaken_d,
    clientIp_s,
    originUrl_s,
    routingRuleName_s
| order by TimeGenerated desc
| take 5
"
```

**What to look for:**
- `originUrl_s`: Where Front Door forwarded the request (Container App)
- `httpStatusCode_d`: The response code from the origin
- `timeTaken_d`: Total time including origin response
- `routingRuleName_s`: The routing rule that matched

---

## Exercise 4: Trace the Request Through APIM

See what APIM logged for OpenAI requests.

```bash
run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.APIMANAGEMENT'
| where Category == 'GatewayLogs'
| project TimeGenerated,
    method=requestMethod_s,
    url=url_s,
    responseCode=responseCode_d,
    backendUrl=backendUrl_s,
    backendResponseCode=backendResponseCode_d,
    totalTime=totalTime_d,
    backendTime=backendTime_d,
    clientIP=callerIpAddress_s,
    correlationId=CorrelationId
| order by TimeGenerated desc
| take 5
"
```

**What to look for:**
- `backendUrl`: The Azure OpenAI endpoint APIM called
- `responseCode` vs `backendResponseCode`: APIM's response vs Azure OpenAI's response
- `totalTime` vs `backendTime`: The difference is APIM processing overhead
- `correlationId`: Use this to trace a single request across all logs

---

## Exercise 5: View Container App Logs

See the application's console output.

```bash
# Container App console logs (application stdout/stderr)
run_query "
ContainerAppConsoleLogs_CL
| where ContainerGroupName_s has '${AZURE_ENV_NAME}'
| project TimeGenerated, Log_s
| order by TimeGenerated desc
| take 20
"
```

If that table is empty, try Application Insights traces:

```bash
run_query "
AppTraces
| project TimeGenerated, Message=message, SeverityLevel=severityLevel
| order by TimeGenerated desc
| take 20
"
```

---

## Exercise 6: View Azure OpenAI Audit Logs

See what prompts and completions were sent to Azure OpenAI.

```bash
run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES'
| project TimeGenerated,
    operationName=operationName_s,
    callerIP=callerIPAddress_s,
    resultType_s,
    properties_s
| order by TimeGenerated desc
| take 10
"
```

**What to look for:**
- `operationName`: Should show `ChatCompletions_Create` or similar
- `callerIPAddress`: Should be APIM's IP (not the user's IP) — this confirms APIM is proxying
- `resultType`: Success or failure

---

## Exercise 7: End-to-End Request Correlation

Tie together logs from multiple layers using timestamps.

```bash
run_query "
let timeWindow = ago(30m);
let frontDoor = AzureDiagnostics 
    | where ResourceProvider == 'MICROSOFT.CDN' 
    | where TimeGenerated > timeWindow
    | where Category == 'FrontDoorAccessLog'
    | summarize fd_requests=count(), fd_avg_time=avg(timeTaken_d) by bin(TimeGenerated, 1m);
let apim = AzureDiagnostics 
    | where ResourceProvider == 'MICROSOFT.APIMANAGEMENT' 
    | where TimeGenerated > timeWindow
    | where Category == 'GatewayLogs'
    | summarize apim_requests=count(), apim_avg_time=avg(totalTime_d) by bin(TimeGenerated, 1m);
let openai = AzureDiagnostics 
    | where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES' 
    | where TimeGenerated > timeWindow
    | summarize oai_requests=count() by bin(TimeGenerated, 1m);
frontDoor
| join kind=leftouter apim on TimeGenerated
| join kind=leftouter openai on TimeGenerated
| project TimeGenerated, fd_requests, fd_avg_time, apim_requests, apim_avg_time, oai_requests
| order by TimeGenerated desc
"
```

**What to look for:**
- Request counts should roughly match across layers (1 user request → 1 AFD → potentially multiple APIM/OpenAI calls for RAG)
- Timing shows latency added at each layer

---

## Exercise 8: Security-Focused Queries

Run queries designed to detect security-relevant events.

### Failed Authentication Attempts

```bash
run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.APIMANAGEMENT'
| where responseCode_d == 401 or responseCode_d == 403
| project TimeGenerated, callerIpAddress_s, url_s, responseCode_d
| order by TimeGenerated desc
| take 10
"
```

### WAF Detections

```bash
run_query "
AzureDiagnostics
| where Category has 'WebApplicationFirewall'
| summarize count() by ruleName_s, action_s
| order by count_ desc
"
```

### Unusual Token Usage

```bash
run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES'
| where operationName_s has 'ChatCompletions'
| project TimeGenerated, callerIPAddress_s, properties_s
| order by TimeGenerated desc
| take 10
"
```

---

## What You Learned

- All resources send diagnostic logs to a central Log Analytics workspace
- You can trace a single request from Front Door → APIM → Azure OpenAI
- KQL (Kusto Query Language) is the query language for Log Analytics
- Each layer logs different metadata (WAF rules, gateway policies, model calls)
- Security queries can detect failed auth, WAF triggers, and unusual usage patterns
- Log ingestion has a 2-10 minute delay — queries may not show the most recent events

## Next Lab

Continue to [Lab 5: Defender for Cloud](lab-5-defender-for-cloud.md) to explore threat detection and security recommendations.
