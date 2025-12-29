// app-service.bicep - Azure App Service for Python web application

param location string
param tags object = {}
param appServicePlanName string
param appServiceName string

// Application configuration
param applicationInsightsConnectionString string
param openAiEndpoint string
param openAiDeploymentName string
param openAiEmbeddingDeploymentName string
param searchEndpoint string
param searchIndexName string
param storageAccountName string
param storageBlobEndpoint string
param cosmosDbEndpoint string
param cosmosDbDatabaseName string
param cosmosDbContainerName string

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

// App Service
resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: appServiceName
  location: location
  tags: union(tags, { 'azd-service-name': 'backend' })
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: appServicePlanSku != 'B1' // AlwaysOn not available on B1
      appCommandLine: 'python -m uvicorn main:app --host 0.0.0.0 --port 8000'
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
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
          name: 'AZURE_OPENAI_EMBEDDING_DEPLOYMENT'
          value: openAiEmbeddingDeploymentName
        }
        {
          name: 'AZURE_SEARCH_ENDPOINT'
          value: searchEndpoint
        }
        {
          name: 'AZURE_SEARCH_INDEX_NAME'
          value: searchIndexName
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
        {
          name: 'AZURE_STORAGE_BLOB_ENDPOINT'
          value: storageBlobEndpoint
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
          name: 'FORWARDED_ALLOW_IPS'
          value: '*'
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
