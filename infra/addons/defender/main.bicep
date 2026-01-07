// Add-on: Enable Microsoft Defender for Cloud plans
//
// IMPORTANT
// - This deployment enables subscription-scoped Defender plans (billing + coverage).
// - It is NOT resource-scoped. If you run it in a shared subscription, it will apply to that subscription.
// - Guardrail: nothing is enabled unless confirmSubscriptionWideEnablement=true.

targetScope = 'subscription'

@description('Guardrail. Must be set to true to enable any Defender plans in this subscription.')
param confirmSubscriptionWideEnablement bool = false

@description('Enable Defender for App Services plan (subscription-wide). Relevant if you deploy App Service / Functions in this subscription.')
param enableDefenderForAppServices bool = false

@description('Enable Defender for Cosmos DB plan (subscription-wide).')
param enableDefenderForCosmosDb bool = false

@description('Enable Defender for Containers plan (subscription-wide). Relevant if you deploy Container Apps / AKS / container workloads in this subscription.')
param enableDefenderForContainers bool = false

@description('Enable Defender for APIs plan (subscription-wide). Relevant for API posture/protection scenarios when supported in your subscription.')
param enableDefenderForApis bool = false

@description('Enable Defender for Storage plan (subscription-wide). Resource-level settings (malware scanning / SDD) are configured separately per storage account.')
param enableDefenderForStorage bool = false

@description('Optional additional Defender pricing plan names to enable (subscription-wide). Use `az security pricing list` to discover plan names in your subscription.')
param additionalPricingPlanNames array = []

var doEnable = confirmSubscriptionWideEnablement

var requestedPricingPlanNames = concat(
  enableDefenderForAppServices ? ['AppServices'] : [],
  enableDefenderForCosmosDb ? ['CosmosDbs'] : [],
  enableDefenderForContainers ? ['Containers'] : [],
  enableDefenderForApis ? ['Api'] : [],
  enableDefenderForStorage ? ['StorageAccounts'] : [],
  additionalPricingPlanNames
)

resource defenderPricingPlans 'Microsoft.Security/pricings@2024-01-01' = [for planName in requestedPricingPlanNames: if (doEnable) {
  name: planName
  properties: {
    pricingTier: 'Standard'
  }
}]

output subscriptionWideEnablementConfirmed bool = confirmSubscriptionWideEnablement
output defenderForAppServicesEnabled bool = doEnable && enableDefenderForAppServices
output defenderForCosmosDbEnabled bool = doEnable && enableDefenderForCosmosDb
output defenderForContainersEnabled bool = doEnable && enableDefenderForContainers
output defenderForApisEnabled bool = doEnable && enableDefenderForApis
output defenderForStorageEnabled bool = doEnable && enableDefenderForStorage
output additionalPricingPlanNamesEnabled array = doEnable ? additionalPricingPlanNames : []
