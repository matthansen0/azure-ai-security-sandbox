// app-service.bicep - Azure App Service running azure-search-openai-demo container

param location string
param tags object = {}
param appServicePlanName string
param appServiceName string
param resourceGroupName string
param azureSubscriptionId string

// Application configuration
param applicationInsightsConnectionString string
param openAiEndpoint string
param openAiDeploymentName string
param openAiEmbeddingDeploymentName string
param openAiAccountName string
param searchEndpoint string
param searchServiceName string
param searchIndexName string
param storageAccountName string
param storageBlobEndpoint string
param cosmosDbEndpoint string
param cosmosDbDatabaseName string
param cosmosDbContainerName string

// Keys and defaults
var openAiKey = listKeys(resourceId('Microsoft.CognitiveServices/accounts', openAiAccountName), '2024-04-01-preview').key1
var searchAdminKey = listAdminKeys(resourceId('Microsoft.Search/searchServices', searchServiceName), '2024-03-01-preview').primaryKey
var resolvedSearchIndexName = !empty(trim(searchIndexName)) ? searchIndexName : 'gptkbindex'
var storageContainer = 'content'

// Container image for azure-search-openai-demo
var containerImage = 'mcr.microsoft.com/azure-search-openai-demo:latest'

@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2', 'P0v3', 'P1v3', 'P2v3', 'P3v3'])
param appServicePlanSku string = 'P0v3'

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux
  }
}

// App Service running container
resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: appServiceName
  location: location
  tags: union(tags, { 'azd-service-name': 'backend' })
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOCKER|${containerImage}'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: appServicePlanSku != 'B1' // AlwaysOn not available on B1
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          name: 'FORWARDED_ALLOW_IPS'
          value: '*'
        }
        {
          name: 'ALLOWED_ORIGIN'
          value: '*'
        }
        {
          name: 'AZURE_SUBSCRIPTION_ID'
          value: azureSubscriptionId
        }
        {
          name: 'AZURE_STORAGE_RESOURCE_GROUP'
          value: resourceGroupName
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT'
          value: storageAccountName
        }
        {
          name: 'AZURE_STORAGE_BLOB_ENDPOINT'
          value: storageBlobEndpoint
        }
        {
          name: 'AZURE_STORAGE_CONTAINER'
          value: storageContainer
        }
        {
          name: 'AZURE_OPENAI_SERVICE'
          value: openAiAccountName
        }
        {
          name: 'AZURE_OPENAI_ENDPOINT'
          value: openAiEndpoint
        }
        {
          name: 'AZURE_OPENAI_CHAT_DEPLOYMENT'
          value: openAiDeploymentName
        }
        {
          name: 'AZURE_OPENAI_CHATGPT_DEPLOYMENT'
          value: openAiDeploymentName
        }
        {
          name: 'AZURE_OPENAI_EMBEDDING_DEPLOYMENT'
          value: openAiEmbeddingDeploymentName
        }
        {
          name: 'AZURE_OPENAI_EMB_DEPLOYMENT'
          value: openAiEmbeddingDeploymentName
        }
        {
          name: 'AZURE_OPENAI_EMB_MODEL_NAME'
          value: 'text-embedding-3-small'
        }
        {
          name: 'AZURE_OPENAI_EMB_DIMENSIONS'
          value: '1536'
        }
        {
          name: 'AZURE_OPENAI_API_KEY_OVERRIDE'
          value: openAiKey
        }
        {
          name: 'OPENAI_API_KEY'
          value: openAiKey
        }
        {
          name: 'AZURE_SEARCH_SERVICE'
          value: searchServiceName
        }
        {
          name: 'AZURE_SEARCH_ENDPOINT'
          value: searchEndpoint
        }
        {
          name: 'AZURE_SEARCH_INDEX'
          value: resolvedSearchIndexName
        }
        {
          name: 'AZURE_SEARCH_INDEX_NAME'
          value: resolvedSearchIndexName
        }
        {
          name: 'AZURE_SEARCH_KEY'
          value: searchAdminKey
        }
        {
          name: 'AZURE_SEARCH_FIELD_NAME_EMBEDDING'
          value: 'embedding'
        }
        {
          name: 'AZURE_SEARCH_SEMANTIC_RANKER'
          value: 'free'
        }
        {
          name: 'AZURE_SEARCH_QUERY_LANGUAGE'
          value: 'en-us'
        }
        {
          name: 'AZURE_SEARCH_QUERY_SPELLER'
          value: 'lexicon'
        }
        {
          name: 'AZURE_SEARCH_QUERY_REWRITING'
          value: 'false'
        }
        {
          name: 'AZURE_SEARCH_KNOWLEDGEBASE_NAME'
          value: ''
        }
        {
          name: 'AZURE_COSMOSDB_ENDPOINT'
          value: cosmosDbEndpoint
        }
        {
          name: 'AZURE_COSMOSDB_DATABASE_NAME'
          value: cosmosDbDatabaseName
        }
        {
          name: 'AZURE_COSMOSDB_CONTAINER_NAME'
          value: cosmosDbContainerName
        }
        {
          name: 'AZURE_ENABLE_UNAUTHENTICATED_ACCESS'
          value: 'true'
        }
        {
          name: 'AZURE_ENFORCE_ACCESS_CONTROL'
          value: 'false'
        }
        {
          name: 'AZURE_USE_AUTHENTICATION'
          value: ''
        }
        {
          name: 'RUNNING_IN_PRODUCTION'
          value: 'true'
        }
        {
          name: 'USE_VECTORS'
          value: 'true'
        }
        {
          name: 'USE_USER_UPLOAD'
          value: 'true'
        }
        {
          name: 'USE_CHAT_HISTORY_BROWSER'
          value: 'true'
        }
        {
          name: 'USE_CHAT_HISTORY_COSMOS'
          value: 'false'
        }
        {
          name: 'USE_MULTIMODAL'
          value: 'false'
        }
        {
          name: 'USE_WEB_SOURCE'
          value: 'false'
        }
        {
          name: 'USE_SHAREPOINT_SOURCE'
          value: 'false'
        }
        {
          name: 'USE_SPEECH_INPUT_BROWSER'
          value: 'false'
        }
        {
          name: 'USE_SPEECH_OUTPUT_BROWSER'
          value: 'false'
        }
        {
          name: 'USE_SPEECH_OUTPUT_AZURE'
          value: 'false'
        }
        {
          name: 'ENABLE_LANGUAGE_PICKER'
          value: 'false'
        }
        {
          name: 'APP_LOG_LEVEL'
          value: 'INFO'
        }
      ]
    }
  }
}

// Logging configuration
resource appServiceLogging 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: appService
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Information'
      }
    }
    httpLogs: {
      fileSystem: {
        enabled: true
        retentionInDays: 7
        retentionInMb: 35
      }
    }
    detailedErrorMessages: {
      enabled: true
    }
    failedRequestsTracing: {
      enabled: true
    }
  }
}

output appServiceId string = appService.id
output appServiceName string = appService.name
output defaultHostName string = appService.properties.defaultHostName
output identityPrincipalId string = appService.identity.principalId
