# Lab 4: Monitoring & Log Analytics

**Objective:** Trace a request end-to-end through all security layers using Log Analytics and KQL queries. Learn to query diagnostic logs from Front Door, APIM, Container Apps, and Azure OpenAI.

**Time:** ~30 minutes

**Requires:** Base deployment (ideally with APIM and AFD enabled for full coverage)

---

## Exercise 1: Generate Traceable Traffic

Open the chat web app in your browser (the `APP_PUBLIC_URL` from the [prerequisites](README.md#prerequisites)) and ask a few questions that exercise the full RAG pipeline:

- "What is Northwind Health Plus?"
- "What are the deductibles?"
- "Tell me about PerksPlus"

> **Note:** Wait 2-5 minutes for logs to appear in Log Analytics before proceeding.

---

## Exercise 2: Open Log Analytics and Verify Data

1. In the Azure Portal, go to your resource group (`rg-<your-env-name>`).
2. Click on the **Log Analytics workspace** (named `log-*`).
3. In the left menu, click **Logs**. Close any sample query pop-ups.
4. Run this KQL query to see which log tables have data:

   ```kusto
   search *
   | distinct $table
   | sort by $table asc
   ```

**What to look for:** Tables that should have data:
- `AzureDiagnostics` — Front Door WAF logs, APIM gateway logs, Azure OpenAI audit logs
- `ContainerAppConsoleLogs_CL` or `ContainerAppSystemLogs_CL` — Container App logs
- `AppTraces`, `AppRequests`, `AppDependencies` — Application Insights telemetry

---

## Exercise 3: Trace a Request Through Front Door

1. Still in the Log Analytics **Logs** blade, paste and run:

   ```kusto
   AzureDiagnostics
   | where ResourceProvider == "MICROSOFT.CDN"
   | where Category == "FrontDoorAccessLog"
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
   ```

**What to look for:**
- `originUrl_s`: Where Front Door forwarded the request (the Container App)
- `httpStatusCode_d`: The response code (should be 200)
- `timeTaken_d`: Total time including origin response
- `clientIp_s`: Your public IP address

---

## Exercise 4: Trace the Request Through APIM

Paste and run this query in the same **Logs** blade:

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.APIMANAGEMENT"
| where Category == "GatewayLogs"
| project TimeGenerated,
    method = requestMethod_s,
    url = url_s,
    responseCode = responseCode_d,
    backendUrl = backendUrl_s,
    backendResponseCode = backendResponseCode_d,
    totalTime = totalTime_d,
    backendTime = backendTime_d,
    clientIP = callerIpAddress_s,
    correlationId = CorrelationId
| order by TimeGenerated desc
| take 5
```

**What to look for:**
- `backendUrl`: The Azure OpenAI endpoint APIM called
- `responseCode` vs `backendResponseCode`: APIM's response vs Azure OpenAI's response (both should be 200)
- `totalTime` vs `backendTime`: The difference is APIM processing overhead
- `correlationId`: Useful for tracing a single request across logs

---

## Exercise 5: View Container App Logs

Paste and run:

```kusto
ContainerAppConsoleLogs_CL
| project TimeGenerated, Log_s
| order by TimeGenerated desc
| take 20
```

If that table is empty, try Application Insights traces instead:

```kusto
AppTraces
| project TimeGenerated, Message = message, SeverityLevel = severityLevel
| order by TimeGenerated desc
| take 20
```

---

## Exercise 6: View Azure OpenAI Audit Logs

Paste and run:

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| project TimeGenerated,
    operationName = operationName_s,
    callerIP = callerIPAddress_s,
    resultType_s,
    properties_s
| order by TimeGenerated desc
| take 10
```

**What to look for:**
- `operationName`: Should show `ChatCompletions_Create` or similar
- `callerIPAddress`: Should be **APIM's IP** (not the user's IP) — confirms APIM is proxying
- `resultType`: Success or failure

---

## Exercise 7: End-to-End Request Correlation

This query ties together logs from multiple layers using time bucketing:

```kusto
let timeWindow = ago(30m);
let frontDoor = AzureDiagnostics
    | where ResourceProvider == "MICROSOFT.CDN"
    | where TimeGenerated > timeWindow
    | where Category == "FrontDoorAccessLog"
    | summarize fd_requests = count(), fd_avg_time = avg(timeTaken_d) by bin(TimeGenerated, 1m);
let apim = AzureDiagnostics
    | where ResourceProvider == "MICROSOFT.APIMANAGEMENT"
    | where TimeGenerated > timeWindow
    | where Category == "GatewayLogs"
    | summarize apim_requests = count(), apim_avg_time = avg(totalTime_d) by bin(TimeGenerated, 1m);
let openai = AzureDiagnostics
    | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
    | where TimeGenerated > timeWindow
    | summarize oai_requests = count() by bin(TimeGenerated, 1m);
frontDoor
| join kind=leftouter apim on TimeGenerated
| join kind=leftouter openai on TimeGenerated
| project TimeGenerated, fd_requests, fd_avg_time, apim_requests, apim_avg_time, oai_requests
| order by TimeGenerated desc
```

**What to look for:**
- Request counts should roughly match across layers (1 user question → 1 AFD request → multiple APIM/OpenAI calls for RAG: embedding + chat completion)
- Timing shows latency added at each layer

---

## Exercise 8: Security-Focused Queries

Run these queries to detect security-relevant events.

### Failed Authentication Attempts

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.APIMANAGEMENT"
| where responseCode_d == 401 or responseCode_d == 403
| project TimeGenerated, callerIpAddress_s, url_s, responseCode_d
| order by TimeGenerated desc
| take 10
```

### WAF Detections

```kusto
AzureDiagnostics
| where Category has "WebApplicationFirewall"
| summarize count() by ruleName_s, action_s
| order by count_ desc
```

### Azure OpenAI Call Patterns

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where operationName_s has "ChatCompletions"
| project TimeGenerated, callerIPAddress_s, properties_s
| order by TimeGenerated desc
| take 10
```

---

## What You Learned

- All resources send diagnostic logs to a central **Log Analytics workspace**
- You can trace a single request from **Front Door → APIM → Azure OpenAI** in the Portal
- **KQL** (Kusto Query Language) is the query language for Log Analytics
- Each layer logs different metadata (WAF rules, gateway policies, model calls)
- Security queries can detect failed auth, WAF triggers, and unusual usage patterns
- Log ingestion has a 2-10 minute delay — queries may not show the most recent events

## Next Lab

Continue to [Lab 5: Defender for Cloud](lab-5-defender-for-cloud.md) to explore threat detection and security recommendations.
