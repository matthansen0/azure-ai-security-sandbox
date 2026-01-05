// container-apps.bicep - Azure Container Apps for azure-search-openai-demo

param location string
param tags object = {}
param containerAppsEnvName string
param containerAppName string
param resourceGroupName string
param azureSubscriptionId string

// Container Registry (for azd deploy image builds)
param containerRegistryName string
param containerRegistryLoginServer string

// Image name - injected by azd deploy; empty on first provision
param imageName string = ''

// Application configuration
param applicationInsightsConnectionString string
param logAnalyticsWorkspaceId string
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

// AI Gateway (APIM) parameters - optional, when provided routes OpenAI traffic through APIM
@description('APIM Gateway URL for AI Gateway routing (e.g., https://apim-xxx.azure-api.net/openai)')
param apimOpenAiEndpoint string = ''

@description('APIM subscription key for AI Gateway authentication')
@secure()
param apimSubscriptionKey string = ''

// Determine if APIM routing is enabled
var useApimGateway = !empty(apimOpenAiEndpoint) && !empty(apimSubscriptionKey)

// Always keep AZURE_OPENAI_ENDPOINT pointing at the real Azure OpenAI resource.
// The upstream app uses AZURE_OPENAI_CUSTOM_URL as the request base URL when OPENAI_HOST=azure_custom.
var resolvedOpenAiEndpoint = openAiEndpoint

// The upstream app (OpenAI SDK) uses base_url like: https://{endpoint}/openai/v1
// Our APIM API path is /openai, so the APIM base_url should be: https://{apim}/openai/v1
var apimOpenAiBaseUrlV1 = useApimGateway ? '${apimOpenAiEndpoint}/v1' : ''

// Keys and defaults - only retrieve OpenAI key if not using APIM
var openAiKey = useApimGateway ? '' : listKeys(resourceId('Microsoft.CognitiveServices/accounts', openAiAccountName), '2024-04-01-preview').key1
var searchAdminKey = listAdminKeys(resourceId('Microsoft.Search/searchServices', searchServiceName), '2024-03-01-preview').primaryKey
var resolvedSearchIndexName = !empty(trim(searchIndexName)) ? searchIndexName : 'gptkbindex'
var storageContainer = 'content'

// Container image - use placeholder during initial provision, real image after azd deploy
var containerImage = !empty(imageName) ? imageName : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// Get ACR credentials for registry auth
var registryPassword = listCredentials(resourceId('Microsoft.ContainerRegistry/registries', containerRegistryName), '2023-07-01').passwords[0].value

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2023-09-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2023-09-01').primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

// Container App - Main RAG application
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'backend' })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
          allowedHeaders: ['*']
        }
      }
      registries: [
        {
          server: containerRegistryLoginServer
          username: containerRegistryName
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: registryPassword
        }
        {
          name: 'openai-api-key'
          // When using APIM Gateway, use APIM subscription key; otherwise use direct OpenAI key
          value: useApimGateway ? apimSubscriptionKey : openAiKey
        }
        {
          name: 'search-api-key'
          value: searchAdminKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'main'
          image: containerImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
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
              // Always the real Azure OpenAI endpoint; required by some upstream components even when routing via APIM.
              value: resolvedOpenAiEndpoint
            }
            {
              // When APIM is enabled, use 'azure_custom' to allow custom URL routing through the gateway
              name: 'OPENAI_HOST'
              value: useApimGateway ? 'azure_custom' : 'azure'
            }
            {
              // Custom base_url used by the upstream OpenAI SDK when OPENAI_HOST=azure_custom.
              // Upstream uses base_url patterns ending in /openai/v1, so APIM must expose /openai/v1/*.
              name: 'AZURE_OPENAI_CUSTOM_URL'
              value: apimOpenAiBaseUrlV1
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
              name: 'AZURE_OPENAI_CHATGPT_MODEL'
              value: 'gpt-4o'
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
              secretRef: 'openai-api-key'
            }
            {
              name: 'OPENAI_API_KEY'
              secretRef: 'openai-api-key'
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
              secretRef: 'search-api-key'
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
              name: 'RUNNING_IN_PRODUCTION'
              value: 'true'
            }
            {
              name: 'USE_VECTORS'
              value: 'true'
            }
            {
              name: 'USE_USER_UPLOAD'
              value: 'false'
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
              name: 'APP_LOG_LEVEL'
              value: 'INFO'
            }
            {
              name: 'ALLOWED_ORIGIN'
              value: '*'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppsEnvironmentId string = containerAppsEnvironment.id
output containerAppsEnvironmentName string = containerAppsEnvironment.name
output containerAppId string = containerApp.id
output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output identityPrincipalId string = containerApp.identity.principalId
output imageName string = containerImage
output usesApimGateway bool = useApimGateway
output configuredOpenAiEndpoint string = resolvedOpenAiEndpoint
