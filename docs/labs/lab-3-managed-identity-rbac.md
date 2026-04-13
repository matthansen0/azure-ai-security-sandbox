# Lab 3: Managed Identity & RBAC

**Objective:** Verify the zero-secrets identity architecture. Understand how managed identities replace API keys and how RBAC role assignments control access between services.

**Time:** ~20 minutes

**Requires:** Base deployment

---

## Exercise 1: Identify All Managed Identities

Every service-to-service connection uses managed identity instead of connection strings or API keys.

```bash
# List all resources with managed identities in the resource group
az resource list -g "$RG" \
  --query "[?identity != null].{name: name, type: type, identityType: identity.type}" -o table
```

**What to look for:**
- **Container App** — `SystemAssigned` identity (the RAG application)
- **API Management** — `SystemAssigned` identity (the AI Gateway)
- If agents are deployed: **Agent Container App** — `SystemAssigned` identity

Each of these identities has its own Azure AD service principal with specific RBAC roles.

---

## Exercise 2: Map the Container App's Role Assignments

The Container App needs access to multiple backend services. Let's verify each role assignment.

```bash
# Get the Container App's managed identity principal ID
CA_PRINCIPAL=$(az containerapp list -g "$RG" \
  --query "[?contains(name, 'ca-')].identity.principalId | [0]" -o tsv)
echo "Container App Principal: $CA_PRINCIPAL"

# List ALL role assignments for this identity
az role assignment list --assignee "$CA_PRINCIPAL" --all \
  --query "[].{role: roleDefinitionName, scope: scope}" -o table
```

**Expected role assignments:**

| Role | Resource | Purpose |
|------|----------|---------|
| `Cognitive Services OpenAI User` | Azure OpenAI | Call GPT-4o and embedding models |
| `Search Index Data Contributor` | AI Search | Read/write search index data |
| `Search Service Contributor` | AI Search | Create and manage indexes |
| `Storage Blob Data Contributor` | Storage Account | Read/write document blobs |

> **Note:** Cosmos DB uses its own RBAC system (SQL role assignments), not ARM role definitions. We verify that separately.

---

## Exercise 3: Verify Cosmos DB SQL Role Assignment

Cosmos DB has its own RBAC system. Let's verify the Container App can access it.

```bash
# Get the Cosmos DB account name
COSMOS_NAME=$(az cosmosdb list -g "$RG" --query "[0].name" -o tsv)
echo "Cosmos DB: $COSMOS_NAME"

# List Cosmos DB SQL role assignments
az cosmosdb sql role assignment list \
  --account-name "$COSMOS_NAME" \
  -g "$RG" \
  --query "[].{principalId: principalId, roleDefinitionId: roleDefinitionId, scope: scope}" -o table
```

**What to look for:**
- The Container App's principal ID should appear with the built-in Data Contributor role
- Role definition ID ending in `00000000-0000-0000-0000-000000000002` is the "Cosmos DB Built-in Data Contributor"

---

## Exercise 4: Verify No API Keys Are Used

One of the key security features is that no API keys exist in environment variables.

```bash
# Check Container App environment variables
az containerapp show \
  -n "$(az containerapp list -g "$RG" --query "[?contains(name, 'ca-')].name | [0]" -o tsv)" \
  -g "$RG" \
  --query "properties.template.containers[0].env[].name" -o tsv | sort
```

**What to look for:**
- `AZURE_OPENAI_ENDPOINT` — The endpoint URL (not a secret)
- `AZURE_OPENAI_CHAT_DEPLOYMENT` — Model deployment name (not a secret)
- **No** `AZURE_OPENAI_API_KEY` environment variable (identity is used instead)
- If APIM is enabled: `OPENAI_HOST=azure_custom` and an APIM subscription key (for app→APIM auth only)

```bash
# Verify: search for any env var that looks like a direct OpenAI key
az containerapp show \
  -n "$(az containerapp list -g "$RG" --query "[?contains(name, 'ca-')].name | [0]" -o tsv)" \
  -g "$RG" \
  --query "properties.template.containers[0].env[?contains(name, 'OPENAI_API_KEY')]" -o json
```

This should return an empty array `[]` — the app uses `DefaultAzureCredential` (managed identity) to authenticate.

---

## Exercise 5: Verify APIM's Identity and Roles

APIM authenticates to Azure OpenAI using its own managed identity, separate from the Container App.

```bash
# Get APIM's managed identity principal
APIM_NAME=$(az apim list -g "$RG" --query "[0].name" -o tsv)
APIM_PRINCIPAL=$(az apim show -g "$RG" -n "$APIM_NAME" \
  --query "identity.principalId" -o tsv)
echo "APIM Principal: $APIM_PRINCIPAL"

# List APIM's role assignments
az role assignment list --assignee "$APIM_PRINCIPAL" --all \
  --query "[].{role: roleDefinitionName, scope: scope}" -o table
```

**What to look for:**
- `Cognitive Services OpenAI Contributor` — APIM can call Azure OpenAI models
- This is a separate principal from the Container App's identity

---

## Exercise 6: Verify the Deploying User's Roles

Your user identity also has role assignments — these are needed for the `postprovision` hook that populates the search index with sample data.

```bash
# List your role assignments in this resource group
az role assignment list --assignee "${AZURE_PRINCIPAL_ID}" \
  --resource-group "$RG" \
  --query "[].{role: roleDefinitionName, scope: scope}" -o table
```

**What to look for:**
- Same roles as the Container App (OpenAI User, Search Contributor, Storage Blob Contributor)
- These let the `prepdocs` script upload documents and create search indexes
- In production, you'd remove these user-level assignments after setup

---

## Exercise 7: Understand the Authentication Chain

Trace how authentication flows through the entire architecture:

```
User → Front Door → Container App → APIM → Azure OpenAI
         (no auth)   (managed ID)  (sub key) (managed ID)
```

```bash
echo "=== Authentication Chain ==="
echo ""
echo "1. User → Front Door: No authentication (public endpoint)"
echo "   (In production, you'd add Azure AD authentication here)"
echo ""
echo "2. Front Door → Container App: Direct routing (AFD origin)"
echo ""
echo "3. Container App → APIM: Subscription key"
echo "   Key stored as Container App secret (not in env vars as plaintext)"
echo ""
echo "4. APIM → Azure OpenAI: Managed identity"
echo "   APIM strips the subscription key and adds a bearer token"
echo ""
echo "5. Container App → AI Search: Managed identity (DefaultAzureCredential)"
echo "6. Container App → Storage: Managed identity"
echo "7. Container App → Cosmos DB: Managed identity"
```

> **Key insight:** API keys only exist at the APIM subscription level (app→APIM). All backend service communication uses managed identity. If a Container App is compromised, the attacker only has access to the specific roles assigned — not admin access to any service.

---

## What You Learned

- Every Azure service uses a **system-assigned managed identity** for authentication
- The Container App has 4 role assignments covering OpenAI, Search, Storage, and Cosmos DB
- APIM has its own separate identity for calling Azure OpenAI
- No API keys for Azure OpenAI exist anywhere in the deployment
- Cosmos DB uses its own SQL RBAC system (separate from ARM RBAC)
- The deploying user also gets role assignments for the setup scripts
- Compromising one identity doesn't give access to all services (least privilege)

## Next Lab

Continue to [Lab 4: Monitoring & Log Analytics](lab-4-monitoring-logging.md) to trace a request end-to-end through all layers.
