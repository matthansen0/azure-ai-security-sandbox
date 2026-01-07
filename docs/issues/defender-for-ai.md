# Issue: Add Defender for AI enablement (add-on)

## Summary
We want to optionally enable/validate **Defender for AI** coverage for this Azure AI Security Sandbox.

This should remain an **explicit add-on** (post-`azd up`) to avoid accidentally enabling subscription-wide Defender plans for unrelated resources in shared subscriptions.

## Why
- This repo is intended as a security reference architecture; we want to cover the Defender surface area where appropriate.
- Defender plan enablement is typically **subscription-scoped**; we need guardrails and clear documentation.

## Current State
- Core deployment does not enable any subscription-wide Defender plans.
- Add-on enables subscription-wide plans via [infra/addons/defender/main.bicep](infra/addons/defender/main.bicep) and [scripts/enable-defender.sh](scripts/enable-defender.sh).
- Defender for AI plan name/availability may vary by tenant/region/preview, so it is not yet enabled by default.

## Acceptance Criteria
- Document what "Defender for AI" means for this architecture (Azure OpenAI / AI Foundry / prompt-injection/jailbreak detection, etc.) and what signals show up where.
- Determine the correct Defender for Cloud plan name(s) in `Microsoft.Security/pricings` for Defender for AI (if applicable) and how to enable them.
- Extend the add-on to support a first-class toggle (e.g., `enableDefenderForAI`) or map to `additionalPricingPlanNames` with clear instructions.
- Provide a verification checklist:
  - Commands to list current pricing plans (`az security pricing list`)
  - Where to see alerts/incidents in Defender for Cloud
  - Any required diagnostic settings / Log Analytics linkage
- Keep the guardrail: require explicit confirmation for subscription-wide enablement.

## Notes / Investigation
- Start by running: `az security pricing list -o table` in a target subscription and capturing the plan names exposed.
- Confirm if Defender for AI is represented as a pricing plan, or if enablement is tied to Defender CSPM/AI workload discovery or other configuration.
