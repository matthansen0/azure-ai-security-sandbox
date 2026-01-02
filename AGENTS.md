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
2. **API Management** - AI Gateway with rate limiting, token tracking, request logging
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
  - `api-management.bicep` - **AI Gateway** with policies (rate limiting, auth, logging)
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
- `backend/` - Python Quart app (from upstream azure-search-openai-demo)
- `backend/Dockerfile` - Container build configuration

### Upstream Submodule (`/upstream`)
- Git submodule pointing to `azure-search-openai-demo`
- Source for app code, prepdocs scripts, and sample data
- **Do not modify files in upstream/** - changes should go in `/app`

### Documentation (`/docs`)
- `CAIRA_INDEX.md` - Cloud AI Risk Assessment index
- Supporting security assessment documents

## Key Files to Understand

| File | Purpose |
|------|---------|
| `azure.yaml` | azd configuration, hooks (postprovision, postdown) |
| `infra/main.bicep` | All configurable parameters live here |
| `infra/modules/api-management.bicep` | AI Gateway policies - rate limits, auth, logging |
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

### Tear Down (with soft-delete purge)
```bash
azd down --force --purge  # Triggers postdown hook to purge APIM and Cognitive Services
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
| `openai.NotFoundError` | See "APIM + OpenAI SDK Integration" section below |

## APIM + OpenAI SDK Integration (Critical!)

This section documents non-obvious behavior when routing OpenAI SDK requests through APIM.

### URL Path Architecture

The upstream `azure-search-openai-demo` uses `OPENAI_HOST=azure_custom` mode with the generic `AsyncOpenAI` client (NOT `AsyncAzureOpenAI`). This has important implications:

**OpenAI SDK URL format** (what the app sends):
```
POST {base_url}/chat/completions
Body: {"model": "gpt-4o", "messages": [...]}
```

**Azure OpenAI URL format** (what Azure expects):
```
POST {endpoint}/openai/deployments/{deployment}/chat/completions?api-version=2024-06-01
```

**APIM must bridge this gap** by rewriting URLs in its inbound policy.

### Container App Environment Variables for APIM

When `useAPIM=true`, the Container App needs these env vars:

| Variable | Value | Purpose |
|----------|-------|---------|
| `OPENAI_HOST` | `azure_custom` | Tells app to use custom URL |
| `AZURE_OPENAI_CUSTOM_URL` | `https://apim-xxx.azure-api.net/openai` | APIM gateway URL (NO trailing `/v1`) |
| `AZURE_OPENAI_API_KEY_OVERRIDE` | APIM subscription key | Authentication to APIM |

**Common mistakes:**
- ❌ `https://apim.../openai/openai` - duplicate path segment
- ❌ `https://apim.../openai/v1` - SDK doesn't use `/v1` for Azure
- ✅ `https://apim.../openai` - correct base URL

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
| `NotFoundError` from OpenAI SDK | URL path wrong or APIM can't route | Check `AZURE_OPENAI_CUSTOM_URL`, verify APIM policy |
| `DeploymentNotFound` | Wrong deployment name | Check `AZURE_OPENAI_CHAT_DEPLOYMENT` matches actual deployment |
| 401 Unauthorized | APIM managed identity missing role | Add "Cognitive Services OpenAI User" role to APIM identity |
| 404 from APIM | No matching operation/route | APIM needs operation for `/chat/completions` with URL rewrite |
| `"Using Azure credential"` in logs | `AZURE_OPENAI_API_KEY_OVERRIDE` empty/missing | Check secret reference in Container App |

## Related Documentation

- [README.md](README.md) - User-facing documentation
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) - Deep dive into every component and why
- [EXECUTIVE_SUMMARY.md](EXECUTIVE_SUMMARY.md) - Business justification
- [CAIRA_ASSESSMENT.md](CAIRA_ASSESSMENT.md) - Security risk assessment
- [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) - Moving from demo to production
