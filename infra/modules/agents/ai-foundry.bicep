// ai-foundry.bicep - Azure AI Foundry Hub and Project for Agent Service
// Deploys the foundation for Azure AI Agent Service

@description('Location for all resources')
param location string

@description('Tags to apply to all resources')
param tags object = {}

@description('Name of the AI Foundry Hub')
param hubName string

@description('Name of the AI Foundry Project')
param projectName string

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('Storage account ID for the hub (required)')
param storageAccountId string

@description('Key Vault ID for the hub (required)')
param keyVaultId string

@description('Application Insights ID for the hub (optional)')
param applicationInsightsId string = ''

@description('Existing Azure OpenAI account name to connect to')
param openAiAccountName string

@description('Existing Azure OpenAI endpoint')
param openAiEndpoint string

@description('Existing Azure AI Search service name to connect to')
param searchServiceName string

@description('Existing Azure AI Search endpoint')
param searchEndpoint string

// AI Foundry Hub (workspace kind = Hub)
resource hub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: hubName
  location: location
  tags: union(tags, { 'azd-service-name': 'ai-foundry-hub' })
  kind: 'Hub'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'AI Security Sandbox Hub'
    description: 'AI Foundry Hub for the Azure AI Security Sandbox'
    storageAccount: storageAccountId
    keyVault: keyVaultId
    applicationInsights: !empty(applicationInsightsId) ? applicationInsightsId : null
    publicNetworkAccess: 'Enabled'  // For demo purposes; use private endpoints in production
  }
}

// AI Foundry Project (workspace kind = Project, linked to Hub)
resource project 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: projectName
  location: location
  tags: union(tags, { 'azd-service-name': 'ai-foundry-project' })
  kind: 'Project'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'IT Admin Agent Project'
    description: 'Project for IT Admin troubleshooting agents'
    hubResourceId: hub.id
    publicNetworkAccess: 'Enabled'
  }
}

// Connection to existing Azure OpenAI
resource openAiConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01' = {
  parent: hub
  name: 'aoai-connection'
  properties: {
    category: 'AzureOpenAI'
    target: openAiEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: resourceId('Microsoft.CognitiveServices/accounts', openAiAccountName)
    }
  }
}

// Connection to existing Azure AI Search
resource searchConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01' = {
  parent: hub
  name: 'search-connection'
  properties: {
    category: 'CognitiveSearch'
    target: searchEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ResourceId: resourceId('Microsoft.Search/searchServices', searchServiceName)
    }
  }
}

// Diagnostic settings for Hub
resource hubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'hub-diagnostics'
  scope: hub
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Diagnostic settings for Project
resource projectDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'project-diagnostics'
  scope: project
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Outputs
output hubId string = hub.id
output hubName string = hub.name
output hubPrincipalId string = hub.identity.principalId
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId

// Project endpoint for Agent Service API
output projectEndpoint string = 'https://${location}.api.azureml.ms/agents/v1.0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.MachineLearningServices/workspaces/${project.name}'
