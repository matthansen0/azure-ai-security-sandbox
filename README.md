# 🤖 Azure AI Security Sandbox 🔐

[![Open in GitHub Codespaces](https://img.shields.io/static/v1?style=for-the-badge&label=GitHub+Codespaces&message=Open&color=brightgreen&logo=github)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=matthansen0%2Fazure-ai-security-sandbox&machine=standardLinux32gb&devcontainer_path=.devcontainer%2Fdevcontainer.json&location=WestUs2)
[![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https%3A%2F%2Fgithub.com%2Fmatthansen0%2Fazure-ai-security-sandbox)

## ✨ Overview

A self-contained Azure AI security demonstration platform featuring a RAG (Retrieval-Augmented Generation) chat application with enterprise-grade security controls. This project deploys everything from scratch using Bicep, pulls the [azure-search-openai-demo](https://github.com/Azure-Samples/azure-search-openai-demo) app from upstream at build time, builds it in Azure Container Registry, and deploys to Azure Container Apps with optional Azure Front Door + WAF. **No application code is stored in this repo**—only infrastructure and a minimal Dockerfile.

> [!WARNING]  
> This repo is under active development for v1.0 release.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Users / Browser                              │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Azure Front Door + WAF (Premium)                   │
│                   • OWASP 3.2 Managed Rules                         │
│                   • Bot Protection                                   │
│                   • Rate Limiting                                    │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Azure Container Apps                              │
│                    • RAG Chat Application (image built via ACR)     │
│                    • Managed Identity                                │
│                    • Auto-scaling                                    │
└───────────┬─────────────────────┼─────────────────────┬─────────────┘
            │                     │                     │
            ▼                     ▼                     ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────────┐
│   Azure OpenAI    │  │  Azure AI Search  │  │    Azure Storage      │
│   • GPT-4o        │  │  • Vector Search  │  │    • Documents        │
│   • Embeddings    │  │  • Semantic       │  │    • Defender         │
│   • Defender AI   │  │    Ranking        │  │    • Malware Scan     │
└───────────────────┘  └───────────────────┘  └───────────────────────┘
            │                                           │
            │                                           ▼
            │                                 ┌───────────────────────┐
            │                                 │    Azure Cosmos DB    │
            │                                 │    • Chat History     │
            │                                 │    • Defender         │
            │                                 └───────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────────────┐
│              Ingestion Pipeline (future: Container Apps Job)          │
└───────────────────────────────────────────────────────────────────────┘
```

## 🔐 Security Features

| Component | Protection | Description |
|-----------|------------|-------------|
| **Front Door + WAF** | Edge Security | OWASP managed rules, bot protection, DDoS mitigation, rate limiting |
| **Defender for AI** | AI Threat Detection | Prompt injection detection, jailbreak attempts, data exfiltration monitoring |
| **Defender for Storage** | Data Protection | Malware scanning on upload, sensitive data discovery (PII/PCI/PHI) |
| **Container Apps** | Serverless Containers | Auto-scaling, managed environment, no infrastructure to manage |
| **Defender for Cosmos DB** | Database Security | SQL injection detection, anomalous access patterns, data exfiltration alerts |
| **Managed Identities** | Zero Secrets | No keys in code—all services authenticate via Azure AD |

## 🚀 Quick Start

### Prerequisites

- Azure subscription with Owner or Contributor access
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) installed
- Azure CLI installed and authenticated
- (Optional) GitHub Codespaces or VS Code with Dev Containers

### Deploy with Azure Developer CLI (Recommended)

The easiest way to deploy is with `azd`:

```bash
# Clone the repository
git clone https://github.com/matthansen0/azure-ai-security-sandbox.git
cd azure-ai-security-sandbox

# Login to Azure
azd auth login

# Deploy everything with one command
azd up
```

That's it! `azd up` will:
1. Prompt you for an environment name and Azure region
2. Provision all infrastructure via Bicep
3. Clone azure-search-openai-demo from GitHub, build the image in ACR, and deploy to Container Apps
4. Configure Front Door routing if `useAFD` is true
5. Output the application URL

To skip Front Door for faster iteration, disable it during provisioning:

```bash
azd up --parameter useAFD=false
```

When Front Door is disabled, `APP_PUBLIC_URL` points directly to the Container App FQDN.

#### Other azd Commands

```bash
azd provision          # Just provision infrastructure (no code deploy needed)
azd down               # Tear down all resources
azd env list           # List environments
azd monitor            # Open Azure Portal monitoring
```

### Deployment Parameters

You can customize the deployment with optional parameters:

```bash
# Deploy to a specific region
azd up --location canadacentral
```

Other useful parameters:

```bash
# Disable Azure Front Door (use Container Apps URL directly)
azd up --parameter useAFD=false

# Keep Defender for App Services and Cosmos DB opt-in (defaults are false)
azd up --parameter enableDefenderForAppServices=false --parameter enableDefenderForCosmosDb=false
```

### Troubleshooting

#### Soft-Deleted Cognitive Services Resource

Azure Cognitive Services (OpenAI) has **enforced soft-delete** (90-day retention). If you delete and redeploy with the same environment name, you may see:

```
FlagMustBeSetForRestore: An existing resource with ID '...' has been soft-deleted. 
To restore the resource, you must specify 'restore' to be 'true' in the property.
```

**Fix:** Redeploy with the restore flag:
```bash
azd up --parameter restoreSoftDeletedOpenAi=true
```

Or purge the soft-deleted resource first:
```bash
az cognitiveservices account list-deleted
az cognitiveservices account purge --name <name> --resource-group <rg> --location <location>
azd up
```

#### Subscription-Level Deployment Conflicts

If you see `InvalidDeploymentLocation` errors when switching regions, delete the stale deployment record:

```bash
az deployment sub delete --name subscriptionSecurity-<environment-name>
azd up --location <new-region>
```

### Deploy with Bash Script (Alternative)

```bash
# Clone the repository
git clone https://github.com/matthansen0/azure-ai-security-sandbox.git
cd azure-ai-security-sandbox

# Login to Azure
az login

# Deploy everything (interactive prompts for region selection)
./deploy.sh
```

### What Gets Deployed

1. **Resource Group** with all resources
2. **Log Analytics Workspace** for monitoring
3. **Azure OpenAI** with GPT-4o and embedding models
4. **Azure AI Search** for document indexing
5. **Azure Storage** for document blobs
6. **Azure Cosmos DB** for chat history
7. **Azure Container Apps** running the RAG application (cloned from upstream and built in ACR at deploy time)
8. **Azure Front Door + WAF** for edge protection (set `useAFD=false` to skip)
9. **Microsoft Defender** for Storage; subscription-level Defender for App Services and Cosmos DB remain opt-in

### Access the Application

After deployment completes, use the Front Door URL (also shown as `APP_PUBLIC_URL` in `azd up` outputs).

```
https://<your-frontdoor-endpoint>.azurefd.net
```

## 📁 Project Structure

```
azure-ai-security-sandbox/
├── app/                        # Application build assets
│   └── backend/               # Dockerfile only (clones upstream at build time)
│       └── Dockerfile
├── infra/                      # Bicep infrastructure
│   ├── main.bicep             # Main orchestration
│   ├── main.parameters.json   # Default parameters
│   └── modules/               # Modular Bicep files
│       ├── ai-services.bicep  # Azure OpenAI + AI Search
│       ├── container-apps.bicep # Container Apps environment + app
│       ├── cosmos-db.bicep    # Cosmos DB for chat history
│       ├── front-door.bicep   # Front Door + WAF
│       ├── functions.bicep    # Azure Functions for doc processing
│       ├── monitoring.bicep   # Log Analytics + App Insights
│       ├── role-assignments.bicep # RBAC for managed identities
│       ├── security.bicep     # Defender configurations
│       ├── storage.bicep      # Storage account
│       └── subscription-security.bicep # Subscription-level Defender
├── docs/                       # Documentation
├── azure.yaml                  # Azure Developer CLI configuration
├── deploy.sh                   # Bash deployment script
├── cleanup.sh                  # Resource cleanup script
└── README.md
```

## 📝 Roadmap

### v1.0 (Current Focus)
- [x] Container Apps deployment (builds from repo and pushes to ACR)
- [x] Bicep-based infrastructure
- [x] Front Door + WAF
- [x] Defender for AI, Storage, Cosmos DB
- [x] Azure OpenAI + AI Search integration
- [ ] Ingestion pipeline (Container Apps Job)
- [ ] Document upload and indexing pipeline
- [ ] Chat with history

### v1.1 (Planned)
- [ ] APIM + Defender for APIs
- [ ] Azure AI Content Safety integration
- [ ] Real architecture diagrams (not ASCII)

### v2.0 (Future)
- [ ] Microsoft Purview for DLP
- [ ] SQL data source + Defender for SQL
- [ ] Data & AI Security Dashboard
- [ ] Private endpoint deployment option

## 🧹 Cleanup

### With azd (Recommended)
```bash
azd down
```

### With Bash Script
```bash
./cleanup.sh
```

Both methods remove all deployed resources and optionally revert any subscription-wide Defender plan changes.

## 📖 Additional Resources

- [Azure OpenAI Landing Zone Reference Architecture](https://techcommunity.microsoft.com/blog/azurearchitectureblog/azure-openai-landing-zone-reference-architecture/3882102)
- [Azure AI Adoption Framework](https://learn.microsoft.com/azure/cloud-adoption-framework/scenarios/ai/)
- [Microsoft Defender for Cloud](https://learn.microsoft.com/azure/defender-for-cloud/)

## 🤝 Contributing

Contributions welcome! Please open an issue first for major changes.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.
