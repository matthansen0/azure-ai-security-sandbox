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
| `USE_APIM` | `true` | Enable AI Gateway |
| `APIM_SKU` | `BasicV2` | APIM SKU (BasicV2, StandardV2) |
| `WAF_MODE` | `Detection` | WAF mode (Detection, Prevention) |

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

## Related Documentation

- [README.md](README.md) - User-facing documentation
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) - Deep dive into every component and why
- [EXECUTIVE_SUMMARY.md](EXECUTIVE_SUMMARY.md) - Business justification
- [CAIRA_ASSESSMENT.md](CAIRA_ASSESSMENT.md) - Security risk assessment
- [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) - Moving from demo to production
