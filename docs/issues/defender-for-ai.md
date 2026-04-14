# Issue: Add Defender for AI enablement (add-on)

**Status:** Implemented in branch `feature/defender-for-ai`

## Summary
We want to optionally enable/validate **Defender for AI** coverage for this Azure AI Security Sandbox.

This should remain an **explicit add-on** (post-`azd up`) to avoid accidentally enabling subscription-wide Defender plans for unrelated resources in shared subscriptions.

## What Was Done
- Added `enableDefenderForAI` toggle to `infra/addons/defender/main.bicep` (plan name: `AI`)
- Updated `scripts/enable-defender.sh` to auto-detect Azure OpenAI endpoint and include the AI plan
- `scripts/disable-defender.sh` already generically rolls back any plan recorded in state — no changes needed
- Created [Lab 7: Defender for AI](../labs/lab-7-defender-for-ai.md) with Portal-first exercises
- Updated README roadmap to mark this item complete

## Scope and Limitations
- **Subscription-scoped only.** Like all Defender plans, Defender for AI is enabled at the subscription level via `Microsoft.Security/pricings`. There is no documented resource-level or resource-group-level enablement for this plan.
- **Plan name: `AI`.** Discovered via `az security pricing list` / ARM REST. If a subscription doesn't expose this plan name, the enable script skips it with a warning.
- **Detection, not blocking.** Defender for AI provides alerts (jailbreak, credential theft, data exfiltration, wallet abuse). Actual blocking of harmful prompts is handled by Azure AI Content Safety / Prompt Shields, configured separately on the Azure OpenAI resource.

## Verification Checklist

### Check available plans
```bash
az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings?api-version=2024-01-01" \
  | jq '.value[] | select(.name == "AI") | {name, tier: .properties.pricingTier}'
```

### Enable via script
```bash
./scripts/enable-defender.sh --confirm
```

### Verify enablement
```bash
az rest --method get \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/AI?api-version=2024-01-01" \
  --query "{plan: name, tier: properties.pricingTier}" -o json
```

### Where to see alerts
- **Azure Portal:** Defender for Cloud → Security alerts (filter by AI resource type)
- **Defender XDR:** security.microsoft.com → Incidents & alerts → Alerts

### Roll back
```bash
./scripts/disable-defender.sh --confirm
```
