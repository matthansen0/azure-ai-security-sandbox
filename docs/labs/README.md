# 🧪 Lab Guides

Hands-on exercises for exploring and verifying the security controls in the Azure AI Security Sandbox. Each lab focuses on a specific security layer and walks you through real verification steps using the Azure CLI, the chat web app, and Log Analytics queries.

## Prerequisites

These labs assume the sandbox is **already deployed** with `azd up`. If you haven't deployed yet, see the [Quick Start](../../README.md#-quick-start) in the main README.

> **Lab 6 (AI Agent Security)** requires the optional agent infrastructure. If you need it, redeploy with `azd up --parameter useAgents=true`.

Before starting any lab, load your environment variables:

```bash
# Load all azd env values into your shell
eval "$(azd env get-values | sed 's/^/export /')"
RG="rg-${AZURE_ENV_NAME}"
```

Then open the chat web app in your browser — you'll use it throughout the labs to generate traffic:

```bash
# Get the application URL and open it
echo "$(azd env get-value APP_PUBLIC_URL)"
```

**Tools required:** Azure CLI (`az`), `curl`, `jq` (all pre-installed in the dev container)

## Lab Overview

| Lab | Topic | Time | Requires |
|-----|-------|------|----------|
| [Lab 1](lab-1-waf-front-door.md) | WAF & Front Door | ~20 min | `useAFD=true` (default) |
| [Lab 2](lab-2-api-management-gateway.md) | API Management AI Gateway | ~25 min | `useAPIM=true` (default) |
| [Lab 3](lab-3-managed-identity-rbac.md) | Managed Identity & RBAC | ~20 min | Base deployment |
| [Lab 4](lab-4-monitoring-logging.md) | Monitoring & Log Analytics | ~30 min | Base deployment |
| [Lab 5](lab-5-defender-for-cloud.md) | Defender for Cloud | ~20 min | Base deployment + add-on script |
| [Lab 6](lab-6-ai-agent-security.md) | AI Agent Security | ~20 min | `useAgents=true` |

## Recommended Order

The labs are designed to be completed in order, following the request flow through the architecture:

```
Lab 1 (Edge) → Lab 2 (Gateway) → Lab 3 (Identity) → Lab 4 (Observability) → Lab 5 (Defender) → Lab 6 (Agents)
```

However, each lab is self-contained and can be completed independently.

## Tips

- **Use the dev container.** All tools are pre-installed and the Azure CLI is already authenticated.
- **WAF propagation takes time.** If you just deployed, WAF rule changes can take 30-45 minutes to take effect.
- **Log Analytics has ingestion delay.** Logs typically appear within 2-5 minutes of an event, but can take up to 10 minutes.
- **Costs add up.** Remember to `azd down --force --purge` when you're done with the labs.
