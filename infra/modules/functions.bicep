// functions.bicep - Azure Functions for document processing pipeline

param location string
param tags object = {}
param functionAppName string
param storageAccountName string
param functionStorageAccountName string
param appServicePlanName string

// Application configuration
param applicationInsightsConnectionString string
param openAiEndpoint string
param openAiDeploymentName string
param openAiEmbeddingDeploymentName string
param openAiAccountName string
param searchEndpoint string
param searchServiceName string
param searchIndexName string
param storageBlobEndpoint string

// Keys
var openAiKey = listKeys(resourceId('Microsoft.CognitiveServices/accounts', openAiAccountName), '2024-04-01-preview').key1
var searchAdminKey = listAdminKeys(resourceId('Microsoft.Search/searchServices', searchServiceName), '2024-03-01-preview').primaryKey
var resolvedSearchIndexName = !empty(trim(searchIndexName)) ? searchIndexName : 'gptkbindex'

// Dedicated storage account for Functions (required for consumption plan)
resource funcStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: functionStorageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

var funcStorageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${funcStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${funcStorageAccount.listKeys().keys[0].value}'

// File service for Functions
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: funcStorageAccount
  name: 'default'
}

// Pre-create file share for Functions (avoids 403 race condition)
resource funcFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: toLower(functionAppName)
  properties: {
    shareQuota: 50
  }
}

// Consumption plan for Functions
resource functionAppPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Linux
  }
}

// Function App for document processing
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'functions' })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [
    funcFileShare
  ]
  properties: {
    serverFarmId: functionAppPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      pythonVersion: '3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: funcStorageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: funcStorageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
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
          value: 'content'
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
          name: 'AZURE_OPENAI_CHATGPT_DEPLOYMENT'
          value: openAiDeploymentName
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
          name: 'AZURE_OPENAI_API_KEY'
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
          name: 'AZURE_SEARCH_KEY'
          value: searchAdminKey
        }
        {
          name: 'AZURE_SEARCH_FIELD_NAME_EMBEDDING'
          value: 'embedding'
        }
        {
          name: 'DOCUMENT_PROCESSING_QUEUE'
          value: 'document-processing'
        }
      ]
    }
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
output identityPrincipalId string = functionApp.identity.principalId
