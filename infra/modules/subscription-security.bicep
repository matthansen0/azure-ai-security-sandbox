// subscription-security.bicep - DEPRECATED
//
// Subscription-wide Defender plan enablement has been moved to an explicit add-on:
// - infra/addons/defender/main.bicep
// - scripts/enable-defender.sh
//
// Reason: Defender plans are subscription-scoped (billing + coverage). Keeping them out of the
// core deployment prevents accidental enablement in shared subscriptions.

targetScope = 'subscription'

param enableDefenderForAppServices bool = false
param enableDefenderForCosmosDb bool = false

// Defender for App Services (subscription-wide, cannot be resource-scoped)
resource defenderForAppServices 'Microsoft.Security/pricings@2024-01-01' = if (enableDefenderForAppServices) {
  name: 'AppServices'
  properties: {
    pricingTier: 'Standard'
  }
}

// Defender for Cosmos DB (subscription-wide, cannot be resource-scoped)
resource defenderForCosmosDb 'Microsoft.Security/pricings@2024-01-01' = if (enableDefenderForCosmosDb) {
  name: 'CosmosDbs'
  properties: {
    pricingTier: 'Standard'
  }
}

// Defender for AI enablement is not implemented here. Track status:
// https://github.com/matthansen0/azure-ai-security-sandbox/issues/14

output defenderForAppServicesEnabled bool = enableDefenderForAppServices
output defenderForCosmosDbEnabled bool = enableDefenderForCosmosDb
