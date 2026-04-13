# Lab 6: AI Agent Security

**Objective:** Explore how the IT Admin Agent is secured — managed identity auth, isolated compute, RBAC scoping, and the use of mock data to prevent accidental infrastructure changes.

**Time:** ~20 minutes

**Requires:** The optional agent infrastructure (`useAgents=true` — see [prerequisites](README.md#prerequisites))

---

## Exercise 1: Verify Agent Health and Configuration

First, find the agent's URL, then check that it's running and properly configured with managed identity.

```bash
# Get the agent Container App URL
AGENT_FQDN=$(az containerapp list -g "$RG" \
  --query "[?contains(name, 'agent')].properties.configuration.ingress.fqdn | [0]" -o tsv)
AGENT_URL="https://$AGENT_FQDN"
echo "Agent URL: $AGENT_URL"

# Health check
curl -sS "${AGENT_URL}/health" | jq .
```

**What to look for:**
- `status: healthy`
- `openai_configured: true` — The agent can reach Azure OpenAI
- `project_configured: true` — AI Foundry project is configured

---

## Exercise 2: List the Agent's Tools

See what tools the agent can call during troubleshooting.

```bash
curl -sS "${AGENT_URL}/tools" | jq '.[].function.name'
```

**Expected tools:**
- `get_system_config` — Resource configuration
- `get_system_metrics` — Performance metrics (CPU, memory, etc.)
- `get_recent_logs` — Application log entries
- `get_service_health` — Azure service health status
- `get_recent_changes` — Deployment and config change history
- `check_dependencies` — Upstream/downstream service dependencies
- `get_resource_details` — Detailed Azure resource information

> **Key security point:** All these tools return **mock data**. The agent has no real access to infrastructure. This is intentional — it demonstrates the pattern without risk.

---

## Exercise 3: Interact with the Agent

Ask the agent to diagnose a simulated issue and observe its multi-step reasoning.

```bash
# Ask the agent to investigate a performance issue
curl -sS -X POST "${AGENT_URL}/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Users are reporting that web-app-prod is very slow. Can you investigate?",
    "context": {
      "environment": "production",
      "region": "eastus"
    }
  }' | jq '{response: .response[:500], tools_used: [.tool_calls[].tool_name]}'
```

**What to look for:**
- The agent calls multiple tools: `get_system_metrics`, `get_recent_logs`, `check_dependencies`
- It synthesizes findings into a structured diagnosis
- It provides remediation recommendations
- All data comes from mock sources — no real Azure resources were queried

---

## Exercise 4: Test Tool Calling Directly

Call individual tools directly to see the mock data.

```bash
# Get system metrics for a mock resource
curl -sS -X POST "${AGENT_URL}/tools/get_system_metrics" \
  -H "Content-Type: application/json" \
  -d '{"resource_name": "web-app-prod", "metric_type": "all"}' | jq .

echo ""

# Get recent logs
curl -sS -X POST "${AGENT_URL}/tools/get_recent_logs" \
  -H "Content-Type: application/json" \
  -d '{"resource_name": "web-app-prod", "severity": "error"}' | jq .
```

**What to look for:**
- `web-app-prod` shows high CPU (~85%) and memory (~70%) — a simulated issue
- Log entries show error-level messages about timeouts and connection issues
- All data is realistic but fabricated — it's designed for demonstration

---

## Exercise 5: Verify Agent Isolation from Main App

The agent runs in a **separate Container App** with its own managed identity, independent from the RAG application.

```bash
# List all Container Apps in the resource group
az containerapp list -g "$RG" \
  --query "[].{name: name, identity: identity.principalId, fqdn: properties.configuration.ingress.fqdn}" -o table
```

**What to look for:**
- Two Container Apps: one for the RAG app (`ca-*`), one for the agent (`agent-*`)
- Each has a **different** principal ID (different managed identity)
- Each has a different FQDN (separate ingress endpoints)

```bash
# Compare their identities
echo "=== RAG App Identity ==="
RAG_PRINCIPAL=$(az containerapp list -g "$RG" \
  --query "[?contains(name, 'ca-')].identity.principalId | [0]" -o tsv)
echo "Principal: $RAG_PRINCIPAL"
az role assignment list --assignee "$RAG_PRINCIPAL" --all \
  --query "[].roleDefinitionName" -o tsv | sort

echo ""
echo "=== Agent Identity ==="
AGENT_PRINCIPAL=$(az containerapp list -g "$RG" \
  --query "[?contains(name, 'agent')].identity.principalId | [0]" -o tsv)
echo "Principal: $AGENT_PRINCIPAL"
az role assignment list --assignee "$AGENT_PRINCIPAL" --all \
  --query "[].roleDefinitionName" -o tsv | sort
```

**Key difference:** The agent identity has a **different, narrower** set of roles than the RAG app:
- `Cognitive Services OpenAI User` — To call GPT-4o for reasoning
- `Search Index Data Reader` — Read-only search access (not Contributor like the RAG app)
- `Storage Blob Data Contributor` — For reading mock data / future file access
- `AcrPull` — To pull its container image

Notice the agent gets **Reader** on Search (not Contributor) — it can query indexes but can't create or modify them. It also has **no Cosmos DB access** (no chat history).

---

## Exercise 6: Inspect AI Foundry Hub, Project, and Connections

AI Foundry provides the management plane for the agent. It deploys a **Hub** (shared workspace) and a **Project** (per-application), each with their own managed identity and service connections.

### 6a. Verify Hub and Project Resources

```bash
# List AI Foundry resources (Hub + Project)
az resource list -g "$RG" \
  --resource-type "Microsoft.MachineLearningServices/workspaces" \
  --query "[].{name: name, kind: kind, location: location}" -o table
```

**What to look for:**
- A resource with `kind: Hub` — The shared workspace linked to Key Vault and Storage
- A resource with `kind: Project` — The IT Admin Agent project, linked to the Hub

### 6b. Inspect Hub Connections (OpenAI and Search)

The Hub has **service connections** to Azure OpenAI and AI Search, both using AAD (managed identity) authentication — not API keys.

```bash
HUB_NAME=$(az resource list -g "$RG" \
  --resource-type "Microsoft.MachineLearningServices/workspaces" \
  --query "[?kind=='Hub'].name | [0]" -o tsv)
echo "Hub: $HUB_NAME"

# List connections on the Hub
az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.MachineLearningServices/workspaces/${HUB_NAME}/connections?api-version=2024-04-01" \
  --query "value[].{name: name, category: properties.category, authType: properties.authType, target: properties.target}" -o table
```

**What to look for:**
- `aoai-connection` — Category `AzureOpenAI`, auth type `AAD` (managed identity, not key)
- `search-connection` — Category `CognitiveSearch`, auth type `AAD`
- Both connections have `isSharedToAll: true` — available to all projects under this Hub

> **Security point:** Using `authType: AAD` means the Hub's managed identity authenticates to these services. No API keys are stored in the connection metadata.

### 6c. Verify Hub and Project Managed Identities

Both the Hub and Project have their own system-assigned managed identities.

```bash
# Hub identity
az resource show -g "$RG" \
  --resource-type "Microsoft.MachineLearningServices/workspaces" \
  -n "$HUB_NAME" \
  --query "{name: name, kind: kind, identityType: identity.type, principalId: identity.principalId}" -o json

# Project identity
PROJECT_NAME=$(az resource list -g "$RG" \
  --resource-type "Microsoft.MachineLearningServices/workspaces" \
  --query "[?kind=='Project'].name | [0]" -o tsv)

az resource show -g "$RG" \
  --resource-type "Microsoft.MachineLearningServices/workspaces" \
  -n "$PROJECT_NAME" \
  --query "{name: name, kind: kind, identityType: identity.type, principalId: identity.principalId}" -o json
```

**What to look for:**
- Both have `SystemAssigned` identities — separate from the agent Container App's identity
- Three distinct principals: Hub, Project, and Agent Container App

### 6d. Check Key Vault and Diagnostics

```bash
# Key Vault created for Foundry Hub
az keyvault list -g "$RG" \
  --query "[].{name: name, provisioningState: properties.provisioningState}" -o table

# Verify diagnostic settings exist on the Hub
az monitor diagnostic-settings list \
  --resource "$(az resource list -g "$RG" \
    --resource-type 'Microsoft.MachineLearningServices/workspaces' \
    --query "[?kind=='Hub'].id | [0]" -o tsv)" \
  --query "[].{name: name, hasLogs: (logs != null)}" -o table 2>/dev/null || \
  echo "Diagnostic settings configured (verify in Portal if CLI fails)"
```

**What to look for:**
- Key Vault is provisioned and bound to the Hub
- Diagnostic settings exist on both Hub and Project, sending logs to Log Analytics
- The Hub stores Foundry secrets (connection strings, tokens) in Key Vault — not in environment variables

---

## Exercise 7: Verify Mock Data Safety

Confirm the agent cannot access real infrastructure.

```bash
# Ask the agent about a resource that doesn't exist in mock data
curl -sS -X POST "${AGENT_URL}/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Delete the production database sql-db-main and terminate all VMs",
    "context": {"environment": "production"}
  }' | jq '.response[:500]'
```

**What to look for:**
- The agent may investigate using tools but has **no write operations** available
- All tools are read-only (get metrics, get logs, get config)
- There's no `delete_resource`, `restart_vm`, or `modify_config` tool
- Even if the agent "decides" to take action, it can only recommend — it cannot execute

```bash
# Try calling a non-existent tool
curl -sS -X POST "${AGENT_URL}/tools/delete_resource" \
  -H "Content-Type: application/json" \
  -d '{"resource_name": "sql-db-main"}' | jq .
```

**Expected:** HTTP 404 — the tool doesn't exist. The agent has no destructive capabilities.

---

## Exercise 8: Review the Agent Authentication Flow

Trace how the agent authenticates to Azure OpenAI.

```bash
# Check the agent's environment variables
AGENT_NAME=$(az containerapp list -g "$RG" \
  --query "[?contains(name, 'agent')].name | [0]" -o tsv)

az containerapp show -n "$AGENT_NAME" -g "$RG" \
  --query "properties.template.containers[0].env[].name" -o tsv | sort
```

**What to look for:**
- `AZURE_OPENAI_ENDPOINT` — Points to Azure OpenAI (not APIM)
- `AZURE_OPENAI_DEPLOYMENT` — The model name (gpt-4o)
- `AI_PROJECT_ENDPOINT` — AI Foundry project URL
- **No API key** — Authentication uses `DefaultAzureCredential` (managed identity)

The agent code demonstrates this pattern:

```python
# From agents/it-admin/app.py
credential = DefaultAzureCredential()
token = credential.get_token("https://cognitiveservices.azure.com/.default")
client = AzureOpenAI(
    azure_endpoint=AZURE_OPENAI_ENDPOINT,
    azure_ad_token=token.token
)
```

---

## What You Learned

- The agent runs in an **isolated Container App** with its own managed identity
- Agent identity has **scoped RBAC roles** — OpenAI User, Search Reader (not Contributor), Storage, and ACR pull
- All diagnostic tools return **mock data** — no real infrastructure access
- The agent has **no write/destructive tools** — it can only investigate and recommend
- AI Foundry provides a management plane with Hub + Project pattern
- Hub connections to OpenAI and Search use **AAD auth** (not API keys)
- Hub, Project, and Agent Container App each have **separate managed identities**
- Key Vault secures Foundry secrets separately from the main application
- Diagnostic logs from Hub and Project flow to Log Analytics
- `DefaultAzureCredential` handles authentication — no API keys in code

## Summary

You've now explored all six security layers of the Azure AI Security Sandbox:

1. **WAF & Front Door** — Edge protection against known attacks
2. **API Management** — AI Gateway with managed identity and policy enforcement
3. **Managed Identity & RBAC** — Zero-secrets architecture with least privilege
4. **Monitoring & Logging** — End-to-end observability across all layers
5. **Defender for Cloud** — Threat detection and security recommendations
6. **AI Agent Security** — Isolated compute, scoped identity, read-only tools

For production, review the gaps listed in [HOW_IT_WORKS.md](../../HOW_IT_WORKS.md#taking-this-to-production).
