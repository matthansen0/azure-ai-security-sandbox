# 🤖 Azure AI Security Sandbox 🔐

[![Open in GitHub Codespaces](https://img.shields.io/static/v1?style=for-the-badge&label=GitHub+Codespaces&message=Open&color=brightgreen&logo=github)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=matthansen0%2Fazure-ai-security-sandbox&machine=standardLinux32gb&devcontainer_path=.devcontainer%2Fdevcontainer.json&location=WestUs2)
[![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https%3A%2F%2Fgithub.com%2Fmatthansen0%2Fazure-ai-security-sandbox)

## ✨ Overview

A self-contained Azure AI security demonstration platform featuring a RAG (Retrieval-Augmented Generation) chat application with enterprise-grade security controls. This project deploys everything from scratch using Bicep—no external dependencies.

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
│                      Azure App Service (Python)                      │
│                      • Managed Identity                              │
│                      • Defender for App Service                      │
└───────────┬─────────────────────┼─────────────────────┬─────────────┘
            │                     │                     │
            ▼                     ▼                     ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────────┐
│   Azure OpenAI    │  │  Azure AI Search  │  │    Azure Storage      │
│   • GPT-4o        │  │  • Vector Search  │  │    • Documents        │
│   • Embeddings    │  │  • Semantic       │  │    • Defender         │
│   • Defender AI   │  │    Ranking        │  │    • Malware Scan     │
└───────────────────┘  └───────────────────┘  └───────────────────────┘
                                                        │
                                                        ▼
                                              ┌───────────────────────┐
                                              │    Azure Cosmos DB    │
                                              │    • Chat History     │
                                              │    • Defender         │
                                              └───────────────────────┘
```

## 🔐 Security Features

| Component | Protection | Description |
|-----------|------------|-------------|
| **Front Door + WAF** | Edge Security | OWASP managed rules, bot protection, DDoS mitigation, rate limiting |
| **Defender for AI** | AI Threat Detection | Prompt injection detection, jailbreak attempts, data exfiltration monitoring |
| **Defender for Storage** | Data Protection | Malware scanning on upload, sensitive data discovery (PII/PCI/PHI) |
| **Defender for App Service** | Runtime Protection | Suspicious process detection, exploitation attempts, brute-force prevention |
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
3. Deploy the Python application to App Service
4. Configure Front Door access restrictions
5. Output the application URL

#### Other azd Commands

```bash
azd provision          # Just provision infrastructure
azd deploy             # Just deploy application code
azd down               # Tear down all resources
azd env list           # List environments
azd monitor            # Open Azure Portal monitoring
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
7. **Azure App Service** running the Python RAG app
8. **Azure Front Door + WAF** for edge protection
9. **Microsoft Defender** plans for all applicable resources

### Access the Application

After deployment completes, access your app via the Front Door URL:

```
https://<your-frontdoor-endpoint>.azurefd.net
```

## 📁 Project Structure

```
azure-ai-security-sandbox/
├── infra/                      # Bicep infrastructure
│   ├── main.bicep             # Main orchestration
│   ├── main.parameters.json   # Default parameters
│   └── modules/               # Modular Bicep files
│       ├── ai-services.bicep
│       ├── app-service.bicep
│       ├── cosmos-db.bicep
│       ├── front-door.bicep
│       ├── monitoring.bicep
│       ├── security.bicep
│       └── storage.bicep
├── src/                        # Application source code
│   └── backend/               # Python FastAPI application
│       ├── app/
│       │   ├── main.py
│       │   ├── chat.py
│       │   ├── search.py
│       │   └── ...
│       ├── requirements.txt
│       └── Dockerfile
├── docs/                       # Documentation
│   └── security-walkthrough.md
├── azure.yaml                  # Azure Developer CLI configuration
├── deploy.sh                   # Bash deployment script
├── cleanup.sh                  # Resource cleanup script
└── README.md
```

## 📝 Roadmap

### v1.0 (Current Focus)
- [x] Self-contained RAG application (no upstream dependencies)
- [x] Bicep-based infrastructure
- [x] Front Door + WAF
- [x] Defender for AI, Storage, App Service, Cosmos DB
- [ ] Complete Python RAG application
- [ ] Document upload and indexing
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
