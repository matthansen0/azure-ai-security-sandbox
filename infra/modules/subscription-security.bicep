// subscription-security.bicep - Subscription-level Defender plans

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

// Defender for AI is automatically enabled when Azure OpenAI resources are created
// and Log Analytics workspace is configured. No explicit pricing resource needed.

output defenderForAppServicesEnabled bool = enableDefenderForAppServices
output defenderForCosmosDbEnabled bool = enableDefenderForCosmosDb
