# Instructions for AI Coding Agents

This file provides context for AI agents (GitHub Copilot, Claude, Cursor, etc.) working on this Azure AI Security Sandbox repository.

**Always keep this file up to date with any changes to the codebase or development process.**

## Project Purpose

This is a **security-focused reference architecture** demonstrating enterprise-grade patterns for deploying Azure OpenAI applications. It wraps the standard `azure-search-openai-demo` RAG application with production security controls.

**Key differentiator:** This is NOT just another RAG demo - it's a security sandbox showing how to properly protect AI workloads in enterprise environments.

## Architecture Overview

```
User → Azure Front Door (WAF) → Azure API Management (AI Gateway) → Container Apps → Azure OpenAI
                                         ↓
                              Azure AI Search ← Sample Data (Northwind Health PDFs)
```

### Security Layers
1. **Azure Front Door** - Global edge with WAF protection (default: Detection mode)
2. **API Management** - AI Gateway with managed identity auth + retry logic (optional rate limiting/token tracking)
3. **Container Apps** - Isolated compute with managed identity
4. **Private Endpoints** - (Optional) Network isolation for backend services
5. **RBAC** - Least-privilege role assignments, no API keys

## Code Layout

> **⚠️ Multiple Project Roots:** This workspace contains TWO project roots:
> 1. **`/` (this repo)** - Security infrastructure and configuration (edit freely)
> 2. **`/upstream/`** - Git submodule of `azure-search-openai-demo` (**read-only, do not modify**)
>
> The upstream submodule has its own `AGENTS.md` - ignore it when working on this project.

### Infrastructure (`/infra`)
- `main.bicep` - Main orchestration, parameters, outputs
- `main.parameters.json` - azd parameter mappings
- `modules/` - Modular Bicep components:
  - `ai-services.bicep` - Azure OpenAI with model deployments
  - `api-management.bicep` - **AI Gateway** with policies (auth + retry; optional rate limiting/token logging)
  - `app-service.bicep` - Container Apps environment and app
  - `container-apps.bicep` - Container Apps with managed identity
  - `container-registry.bicep` - ACR for container images
  - `cosmos-db.bicep` - Chat history storage
  - `front-door.bicep` - AFD + WAF policy
  - `monitoring.bicep` - Log Analytics + App Insights
  - `role-assignments.bicep` - RBAC for managed identities
  - `search.bicep` - Azure AI Search
  - `security.bicep` - Key Vault (optional)
  - `storage.bicep` - Blob storage for documents

### Application (`/app`)
- `backend/Dockerfile` - Container build configuration

### Upstream Submodule (`/upstream`)
- Git submodule pointing to `azure-search-openai-demo`
- Used for prepdocs scripts and sample data
- **Do not modify files in upstream/** - it's a git submodule

> **⚠️ Container Image Build Behavior:**
> The Dockerfile clones `azure-search-openai-demo` **from GitHub at build time** - it does NOT use the local `/upstream` submodule. This means:
> - The deployed container always has the latest `main` branch code
> - Local changes to `/upstream` won't affect the deployed app
> - To understand app behavior, read `/upstream` code (it matches what's deployed)
> - To customize the app, you'd need to modify the Dockerfile to copy local code instead

### Documentation (`/docs`)
- `CAIRA_INDEX.md` - Cloud AI Risk Assessment index
- Supporting security assessment documents

## Key Files to Understand

| File | Purpose |
|------|---------|
| `azure.yaml` | azd configuration, hooks (postprovision, postdown) |
| `infra/main.bicep` | All configurable parameters live here |
| `infra/modules/api-management.bicep` | AI Gateway policies - auth + retry (optional rate limits/token logging) |
| `infra/modules/front-door.bicep` | WAF rules and mode configuration |
| `deploy.sh` / `cleanup.sh` | Manual deployment scripts (prefer azd) |

## Common Operations

### Deploy the Solution
```bash
azd up                           # Full deployment
azd up --parameter useAPIM=false  # Skip APIM for faster iteration
```

### Populate Search Index
The `postprovision` hook in `azure.yaml` automatically runs prepdocs after provisioning.
Manual run:
```bash
cd upstream && ./scripts/prepdocs.sh
```

### Test the Application
```bash
# Get the Front Door URL
azd env get-value SERVICE_BACKEND_URI

# Test a RAG query
curl -X POST "https://<afd-endpoint>/chat" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is Northwind Health Plus?"}]}'
```

### Testing with curl (Detailed)

After deployment, test each layer to isolate issues:

```bash
# 1. Get resource names from azd env
azd env get-values | grep -E "ENDPOINT|URI|GATEWAY"

# 2. Test Container App directly (bypasses Front Door + APIM)
CONTAINER_APP_URL=$(az containerapp show -n ca-<token> -g rg-<env> --query "properties.configuration.ingress.fqdn" -o tsv)
curl -s -X POST "https://${CONTAINER_APP_URL}/chat" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is Northwind Health Plus?"}]}' | jq .

# 3. Test APIM directly (bypasses Front Door, tests APIM → OpenAI)
APIM_KEY=$(az apim subscription keys list -g rg-<env> --service-name apim-<token> \
  --subscription-id internal-apps --query primaryKey -o tsv)
curl -s -X POST "https://apim-<token>.azure-api.net/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
  -H "api-key: ${APIM_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hi"}],"max_tokens":10}' | jq .

# 4. Test through Front Door (full path)
curl -s -X POST "https://<afd-endpoint>/chat" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is Northwind Health Plus?"}]}' | jq .
```

**Expected responses:**
- Container App direct: Full RAG response with citations
- APIM direct: Short OpenAI response (no RAG context)
- Front Door: Same as Container App (full RAG response)

### Tear Down (with soft-delete purge)
```bash
azd down --force --purge  # Triggers postdown hook to purge APIM and Cognitive Services
```

> **Note:** `azd down` can sometimes be flaky. If resources aren't deleted, use:
> ```bash
> az group delete -n rg-<env-name> --yes --no-wait
> ```

### Finding Resources by Token

All resources in an environment share a unique token (e.g., `yemy7aspuew3e`). To find resources:
```bash
# Get the token from any resource name
az resource list -g rg-<env> --query "[].name" -o tsv | head -1 | sed 's/.*-//'

# Or from azd env
azd env get-values | grep -i token
```

## Environment Variables

Set via `azd env set <KEY> <VALUE>`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `AZURE_LOCATION` | (required) | Deployment region |
| `AZURE_ENV_NAME` | (required) | Environment name prefix |
| `AZURE_PRINCIPAL_ID` | (auto) | Deploying user's Object ID (set by azd) |
| `AZURE_PRINCIPAL_TYPE` | `User` | `User` for interactive, `ServicePrincipal` for CI/CD |
| `USE_APIM` | `true` | Enable AI Gateway |
| `APIM_SKU` | `BasicV2` | APIM SKU (BasicV2, StandardV2) |
| `WAF_MODE` | `Detection` | WAF mode (Detection, Prevention) |

## RBAC Architecture

The deployment creates role assignments for TWO principals:
1. **Container App managed identity** - Runtime access (OpenAI, Search, Storage, Cosmos)
2. **Deploying user** - Prepdocs access (uploads blobs, creates search indexes)

This dual-assignment pattern ensures:
- The app runs with least-privilege managed identity
- The postprovision hook can populate the search index
- Works from Cloud Shell, Codespaces, or local VS Code

## Adding New Security Controls

When adding new security features:

1. **Create a new Bicep module** in `infra/modules/`
2. **Wire it up in `main.bicep`** - add parameters, module reference, outputs
3. **Add diagnostic settings** - all resources should log to Log Analytics
4. **Use managed identity** - avoid API keys where possible
5. **Document in README** - update architecture diagram and "What Gets Deployed"
6. **Update this file** - keep AGENTS.md current

## Deployment Timing Reference

| Resource | Typical Time |
|----------|--------------|
| Most resources | < 30 seconds |
| Cosmos DB | ~1-2 minutes |
| APIM (BasicV2) | ~5-10 minutes |

| Front Door | ~10-15 minutes |
| AFD WAF propagation | ~30-45 minutes |

## Things to Avoid

- ❌ **Don't use API keys** - Use managed identity authentication
- ❌ **Don't modify `/upstream`** - It's a git submodule
- ❌ **Don't skip WAF** - Even in Detection mode, it provides visibility
- ❌ **Don't hardcode secrets** - Use Key Vault or azd env variables
- ❌ **Don't forget diagnostic settings** - All resources need logging
- ❌ **Don't use Consumption APIM** - Missing features needed for AI Gateway

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| 403 from Front Door | Check WAF mode (should be Detection for dev) |
| "I don't know" responses | Search index empty - run prepdocs |
| APIM soft-delete conflict | `az apim deletedservice purge --location <loc> --service-name <name>` |
| Cognitive Services conflict | `az cognitiveservices account purge --location <loc> --name <name> -g <rg>` |
| Container not starting | Check ACR image exists, check Container Apps logs |
| `openai.AuthenticationError` | APIM enabled but `OPENAI_HOST` not set to `azure_custom` - redeploy with latest `container-apps.bicep` |
| `openai.NotFoundError` | See "APIM + OpenAI SDK Integration" section below |

## APIM Policy Gotchas (Learned the Hard Way)

### APIM `500` + `ExpressionValueValidationFailure`

If APIM returns HTTP 500 with a body like:
`{"statusCode":500,"message":"Internal server error","activityId":"..."}`

…and Container Apps surfaces it as `openai.InternalServerError`, it can be a *policy expression* failing (not Azure OpenAI).

Symptoms in Log Analytics (APIM `GatewayLogs`):

- `lastError_reason_s`: `ExpressionValueValidationFailure`
- `lastError_message_s`: `Expression value is invalid. The value field is required.`
- `lastError_section_s`: `inbound` or `outbound`

Important: APIM may successfully call Azure OpenAI (HTTP 200) and then still return 500 if an outbound policy expression fails (for example, response body parsing/token counting).

### How to Debug APIM 500s Quickly

1. Get the `activityId` from the APIM 500 response body.
2. Query Log Analytics `AzureDiagnostics` for the matching `CorrelationId`.

This dev container sometimes has a broken `az monitor` module. Work around it by using Log Analytics Query REST API:

```bash
# 1) Get workspace customerId (workspaceId)
WS_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<wsName>"
WORKSPACE_ID=$(az rest --method get --uri "https://management.azure.com${WS_ID}?api-version=2023-09-01" --query properties.customerId -o tsv)

# 2) Query AzureDiagnostics for the APIM correlationId
TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)
CID="<activityId-from-500-body>"
QUERY="AzureDiagnostics | where ResourceProvider == 'MICROSOFT.APIMANAGEMENT' | where CorrelationId == '${CID}' | project TimeGenerated, lastError_section_s, lastError_reason_s, lastError_message_s, traceRecords_s, errors_s | take 1"
curl -sS -X POST "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -nc --arg q "$QUERY" '{query:$q}')" | jq
```

If you see `ExpressionValueValidationFailure`, simplify the policy to the essentials (auth + forward + managed identity) and re-introduce tracing/rate-limit/token parsing incrementally with APIM-supported expression patterns.

## APIM + OpenAI SDK Integration (Critical!)

> **✅ FIXED (Jan 2026):** The Container App now correctly sets `OPENAI_HOST=azure_custom` and `AZURE_OPENAI_CUSTOM_URL` when APIM is enabled. The app uses `AsyncAzureOpenAI` client which constructs Azure-style URLs (`/deployments/{name}/chat/completions`), so APIM routes correctly without needing URL rewrite policies.
>
> **⚠️ STILL PENDING:** If you want to support generic OpenAI SDK clients that send `/chat/completions` (without deployment in path), you'd need to add an APIM operation with URL rewrite policy. This is NOT required for the current implementation.

This section documents non-obvious behavior when routing OpenAI SDK requests through APIM.

### URL Path Architecture

The upstream `azure-search-openai-demo` uses `OPENAI_HOST=azure_custom` mode with the generic `AsyncOpenAI` client (NOT `AsyncAzureOpenAI`). This has important implications:

**OpenAI SDK URL format** (what the app sends):

```text
POST {base_url}/chat/completions
Body: {"model": "gpt-4o", "messages": [...]}
```

**Azure OpenAI URL format** (what Azure expects):

```text
POST {endpoint}/openai/deployments/{deployment}/chat/completions?api-version=2024-06-01
```

**APIM must bridge this gap** by rewriting URLs in its inbound policy.

### Container App Environment Variables for APIM

When `useAPIM=true`, `container-apps.bicep` **automatically configures** these env vars:

| Variable | Value | Purpose |
|----------|-------|---------|
| `OPENAI_HOST` | `azure_custom` | Tells app to use custom URL (auto-set) |
| `AZURE_OPENAI_CUSTOM_URL` | `https://apim-xxx.azure-api.net/openai/v1` | APIM gateway base URL (auto-set) |
| `AZURE_OPENAI_API_KEY_OVERRIDE` | APIM subscription key | Authentication to APIM (auto-set from secret) |

**Common mistakes:**
- ❌ `https://apim.../openai/openai` - duplicate path segment
- ❌ `https://apim.../openai` - missing `/v1` (SDK base_url expects `/openai/v1`)
- ✅ `https://apim.../openai/v1` - correct base URL

### APIM Policy for URL Rewriting

The APIM inbound policy must extract the `model` from the request body and rewrite to Azure format:

```xml
<inbound>
    <!-- Extract model from request body -->
    <set-variable name="requestBody" value="@(context.Request.Body.As<JObject>(preserveContent: true))" />
    <set-variable name="model" value="@((string)((JObject)context.Variables["requestBody"])["model"] ?? "gpt-4o")" />
    
    <!-- Rewrite URL to Azure OpenAI format -->
    <rewrite-uri template="@("/deployments/" + (string)context.Variables["model"] + "/chat/completions")" />
    <set-query-parameter name="api-version" exists-action="override">
        <value>2024-06-01</value>
    </set-query-parameter>
</inbound>
```

### Authentication Flow

```
Container App                    APIM                         Azure OpenAI
     |                            |                                |
     |--- api-key: <sub-key> ---->|                                |
     |                            |--- Authorization: Bearer --->  |
     |                            |    (managed identity token)    |
```

- **Container App → APIM**: Uses APIM subscription key (`api-key` header)
- **APIM → Azure OpenAI**: Uses APIM's managed identity (bearer token)
- APIM deletes incoming `api-key` and adds `Authorization: Bearer <token>`

### Debugging APIM Issues

1. **Test APIM directly** (bypassing Container App):
   ```bash
   # Get subscription key
   az apim subscription keys list --resource-group rg-<env> \
     --service-name apim-<token> --subscription-id internal-apps --query primaryKey -o tsv
   
   # Test Azure-style URL (should work)
   curl -X POST "https://apim-xxx.azure-api.net/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
     -H "api-key: <subscription-key>" \
     -H "Content-Type: application/json" \
     -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
   
   # Test OpenAI-style URL (requires URL rewrite policy)
   curl -X POST "https://apim-xxx.azure-api.net/openai/chat/completions" \
     -H "api-key: <subscription-key>" \
     -H "Content-Type: application/json" \
     -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
   ```

2. **Check Container App logs**:
   ```bash
   az containerapp logs show -n ca-<token> -g rg-<env> --type console --tail 50
   ```
   
   Look for:
   - `"OPENAI_HOST is azure_custom"` - confirms custom URL mode
   - `"AZURE_OPENAI_API_KEY_OVERRIDE found"` - confirms API key auth (good)
   - `"Using Azure credential (passwordless)"` - means API key NOT found (bad for APIM)

3. **Check Container App env vars**:
   ```bash
   az containerapp show -n ca-<token> -g rg-<env> \
     --query "properties.template.containers[0].env" -o table
   ```

### Common Error Patterns

| Error | Cause | Fix |
|-------|-------|-----|
| `AuthenticationError` | `OPENAI_HOST` not set to `azure_custom` when APIM enabled | Run `azd provision` to update Container App with correct env vars |
| `NotFoundError` from OpenAI SDK | URL path wrong or APIM can't route | Check `AZURE_OPENAI_CUSTOM_URL` is set correctly |
| `DeploymentNotFound` | Wrong deployment name | Check `AZURE_OPENAI_CHAT_DEPLOYMENT` matches actual deployment |
| 401 Unauthorized | APIM managed identity missing role | Add "Cognitive Services OpenAI User" role to APIM identity |
| 404 from APIM | No matching operation/route | Verify APIM has `openai` API with correct backend |
| `"Using Azure credential"` in logs | `AZURE_OPENAI_API_KEY_OVERRIDE` empty/missing | Check secret reference in Container App |

## Related Documentation

- [README.md](README.md) - User-facing documentation
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) - Deep dive into every component and why
- [EXECUTIVE_SUMMARY.md](EXECUTIVE_SUMMARY.md) - Business justification
- [CAIRA_ASSESSMENT.md](CAIRA_ASSESSMENT.md) - Security risk assessment
- [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) - Moving from demo to production
