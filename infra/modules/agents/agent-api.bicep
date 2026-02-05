// agent-api.bicep - Container App for IT Admin Agent API
// Deploys a FastAPI application that exposes the IT Admin troubleshooting agent

@description('Location for all resources')
param location string

@description('Tags to apply to all resources')
param tags object = {}

@description('Name of the Container App')
param containerAppName string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Container Registry login server')
param containerRegistryLoginServer string

@description('Container image name (set by azd deploy)')
param imageName string

@description('Application Insights connection string')
param applicationInsightsConnectionString string

@description('Azure OpenAI endpoint')
param openAiEndpoint string

@description('Azure OpenAI deployment name for the agent')
param openAiDeploymentName string

@description('AI Foundry Project endpoint for Agent Service')
param projectEndpoint string

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

// User-assigned managed identity for ACR pull
resource acrPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${containerAppName}-acr-identity'
  location: location
  tags: tags
}

// Container App for Agent API
resource agentApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'agent-api' })
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['*']
        }
      }
      registries: [
        {
          server: containerRegistryLoginServer
          identity: acrPullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'agent-api'
          image: !empty(imageName) ? imageName : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openAiEndpoint
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT'
              value: openAiDeploymentName
            }
            {
              name: 'AI_PROJECT_ENDPOINT'
              value: projectEndpoint
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: ''  // Will use system-assigned managed identity
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// Diagnostic settings
resource agentAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'agent-api-diagnostics'
  scope: agentApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'ContainerAppConsoleLogs'
        enabled: true
      }
      {
        category: 'ContainerAppSystemLogs'
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
output containerAppName string = agentApp.name
output containerAppFqdn string = agentApp.properties.configuration.ingress.fqdn
output identityPrincipalId string = agentApp.identity.principalId
output acrPullIdentityPrincipalId string = acrPullIdentity.properties.principalId
output acrPullIdentityId string = acrPullIdentity.id
output agentApiUrl string = 'https://${agentApp.properties.configuration.ingress.fqdn}'
