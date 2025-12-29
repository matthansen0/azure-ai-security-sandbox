// main.bicep - Azure AI Security Sandbox Infrastructure
// Deploys a complete RAG application with enterprise security controls

targetScope = 'subscription'

@description('Name of the environment (used for resource naming)')
@minLength(1)
@maxLength(20)
param environmentName string

@description('Primary location for all resources')
param location string

@description('Azure OpenAI location (may differ from primary location due to model availability)')
param openAiLocation string = location

@description('Tags to apply to all resources')
param tags object = {}

@description('Enable Defender for App Services at subscription level')
param enableDefenderForAppServices bool = true

@description('Enable Defender for Cosmos DB at subscription level')
param enableDefenderForCosmosDb bool = true

@description('App Service Plan SKU (B1=Basic, S1=Standard, P1v3=Premium)')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2', 'P0v3', 'P1v3', 'P2v3', 'P3v3'])
param appServicePlanSku string = 'B2'

@description('Set to true to restore a soft-deleted OpenAI resource with the same name')
param restoreSoftDeletedOpenAi bool = false

// Generate unique suffix for globally unique resource names
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var abbrs = loadJsonContent('abbreviations.json')

// Resource group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: union(tags, { 'azd-env-name': environmentName })
}

// Monitoring (Log Analytics + App Insights)
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
  }
}

// Storage Account
module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    location: location
    tags: tags
    storageAccountName: '${abbrs.storageStorageAccounts}${resourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// Cosmos DB for chat history
module cosmosDb 'modules/cosmos-db.bicep' = {
  name: 'cosmosDb'
  scope: rg
  params: {
    location: location
    tags: tags
    cosmosDbAccountName: '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// Azure AI Services (OpenAI + AI Search)
module aiServices 'modules/ai-services.bicep' = {
  name: 'aiServices'
  scope: rg
  params: {
    location: location
    openAiLocation: openAiLocation
    tags: tags
    openAiAccountName: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    searchServiceName: '${abbrs.searchSearchServices}${resourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    restoreSoftDeletedOpenAi: restoreSoftDeletedOpenAi
  }
}

// App Service
module appService 'modules/app-service.bicep' = {
  name: 'appService'
  scope: rg
  params: {
    location: location
    tags: tags
    appServicePlanName: '${abbrs.webServerFarms}${resourceToken}'
    appServiceName: '${abbrs.webSitesAppService}${resourceToken}'
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    // App settings for connecting to other services
    openAiEndpoint: aiServices.outputs.openAiEndpoint
    openAiDeploymentName: aiServices.outputs.chatDeploymentName
    openAiEmbeddingDeploymentName: aiServices.outputs.embeddingDeploymentName
    searchEndpoint: aiServices.outputs.searchEndpoint
    searchIndexName: 'documents'
    storageAccountName: storage.outputs.storageAccountName
    storageBlobEndpoint: storage.outputs.blobEndpoint
    cosmosDbEndpoint: cosmosDb.outputs.cosmosDbEndpoint
    cosmosDbDatabaseName: cosmosDb.outputs.databaseName
    cosmosDbContainerName: cosmosDb.outputs.containerName
    appServicePlanSku: appServicePlanSku
  }
}

// Role assignments for managed identity
module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'roleAssignments'
  scope: rg
  params: {
    principalId: appService.outputs.identityPrincipalId
    openAiAccountName: aiServices.outputs.openAiAccountName
    searchServiceName: aiServices.outputs.searchServiceName
    storageAccountName: storage.outputs.storageAccountName
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
  }
}

// Front Door with WAF
module frontDoor 'modules/front-door.bicep' = {
  name: 'frontDoor'
  scope: rg
  params: {
    tags: tags
    frontDoorProfileName: '${abbrs.cdnProfiles}${resourceToken}'
    frontDoorEndpointName: 'ep-${resourceToken}'
    wafPolicyName: 'waf${resourceToken}'
    originHostName: appService.outputs.defaultHostName
  }
}

// Security configurations (Defender plans)
module security 'modules/security.bicep' = {
  name: 'security'
  scope: rg
  params: {
    storageAccountName: storage.outputs.storageAccountName
  }
}

// Subscription-level Defender plans (optional)
module subscriptionSecurity 'modules/subscription-security.bicep' = {
  name: 'subscriptionSecurity-${environmentName}'
  scope: subscription()
  params: {
    enableDefenderForAppServices: enableDefenderForAppServices
    enableDefenderForCosmosDb: enableDefenderForCosmosDb
  }
}

// Outputs
output RESOURCE_GROUP_NAME string = rg.name
output AZURE_LOCATION string = location

// App Service outputs
output APP_SERVICE_NAME string = appService.outputs.appServiceName
output APP_INTERNAL_URL string = 'https://${appService.outputs.defaultHostName}'
// Primary public URL (Front Door)
output APP_PUBLIC_URL string = 'https://${frontDoor.outputs.frontDoorEndpointHostName}'

// Front Door outputs
output FRONTDOOR_ENDPOINT string = frontDoor.outputs.frontDoorEndpointHostName
output FRONTDOOR_URL string = 'https://${frontDoor.outputs.frontDoorEndpointHostName}'
output FRONTDOOR_PROFILE_NAME string = frontDoor.outputs.frontDoorProfileName
output FRONTDOOR_ENDPOINT_NAME string = frontDoor.outputs.frontDoorEndpointName

// AI Services outputs
output AZURE_OPENAI_ENDPOINT string = aiServices.outputs.openAiEndpoint
output AZURE_OPENAI_CHAT_DEPLOYMENT string = aiServices.outputs.chatDeploymentName
output AZURE_OPENAI_EMBEDDING_DEPLOYMENT string = aiServices.outputs.embeddingDeploymentName
output AZURE_SEARCH_ENDPOINT string = aiServices.outputs.searchEndpoint

// Storage outputs
output AZURE_STORAGE_ACCOUNT string = storage.outputs.storageAccountName
output AZURE_STORAGE_BLOB_ENDPOINT string = storage.outputs.blobEndpoint

// Cosmos DB outputs
output AZURE_COSMOSDB_ENDPOINT string = cosmosDb.outputs.cosmosDbEndpoint
