// agent-role-assignments.bicep - RBAC for Agent Service components
// Grants necessary permissions to managed identities

@description('Principal ID of the AI Foundry Hub managed identity')
param hubPrincipalId string

@description('Principal ID of the AI Foundry Project managed identity')
param projectPrincipalId string

@description('Principal ID of the Agent API Container App managed identity')
param agentApiPrincipalId string

@description('Principal ID of the ACR pull identity')
param acrPullIdentityPrincipalId string

@description('Azure OpenAI account name')
param openAiAccountName string

@description('Azure AI Search service name')
param searchServiceName string

@description('Storage account name')
param storageAccountName string

@description('Container Registry name')
param containerRegistryName string

// Built-in role definitions
var cognitiveServicesOpenAiUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
var searchIndexDataContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
var searchIndexDataReaderRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
var storageBlobDataContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var acrPullRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

// Existing resources
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' existing = {
  name: openAiAccountName
}

resource searchService 'Microsoft.Search/searchServices@2024-03-01-preview' existing = {
  name: searchServiceName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

// ============ Agent API Container App Role Assignments ============

// Agent API → Azure OpenAI (Cognitive Services OpenAI User)
resource agentApiOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, agentApiPrincipalId, cognitiveServicesOpenAiUserRole)
  scope: openAiAccount
  properties: {
    principalId: agentApiPrincipalId
    roleDefinitionId: cognitiveServicesOpenAiUserRole
    principalType: 'ServicePrincipal'
  }
}

// Agent API → Azure AI Search (Index Data Reader for RAG queries)
resource agentApiSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, agentApiPrincipalId, searchIndexDataReaderRole)
  scope: searchService
  properties: {
    principalId: agentApiPrincipalId
    roleDefinitionId: searchIndexDataReaderRole
    principalType: 'ServicePrincipal'
  }
}

// Agent API → Storage (Blob Data Contributor for reading mock data / future file access)
resource agentApiStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, agentApiPrincipalId, storageBlobDataContributorRole)
  scope: storageAccount
  properties: {
    principalId: agentApiPrincipalId
    roleDefinitionId: storageBlobDataContributorRole
    principalType: 'ServicePrincipal'
  }
}

// ACR Pull Identity → Container Registry (AcrPull for pulling images)
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, acrPullIdentityPrincipalId, acrPullRole)
  scope: containerRegistry
  properties: {
    principalId: acrPullIdentityPrincipalId
    roleDefinitionId: acrPullRole
    principalType: 'ServicePrincipal'
  }
}

// ============ AI Foundry Hub Role Assignments ============

// Hub → Azure OpenAI
resource hubOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, hubPrincipalId, cognitiveServicesOpenAiUserRole)
  scope: openAiAccount
  properties: {
    principalId: hubPrincipalId
    roleDefinitionId: cognitiveServicesOpenAiUserRole
    principalType: 'ServicePrincipal'
  }
}

// Hub → Storage
resource hubStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, hubPrincipalId, storageBlobDataContributorRole)
  scope: storageAccount
  properties: {
    principalId: hubPrincipalId
    roleDefinitionId: storageBlobDataContributorRole
    principalType: 'ServicePrincipal'
  }
}

// Hub → Search
resource hubSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, hubPrincipalId, searchIndexDataContributorRole)
  scope: searchService
  properties: {
    principalId: hubPrincipalId
    roleDefinitionId: searchIndexDataContributorRole
    principalType: 'ServicePrincipal'
  }
}

// ============ AI Foundry Project Role Assignments ============

// Project → Azure OpenAI
resource projectOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, projectPrincipalId, cognitiveServicesOpenAiUserRole)
  scope: openAiAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cognitiveServicesOpenAiUserRole
    principalType: 'ServicePrincipal'
  }
}

// Project → Storage
resource projectStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, projectPrincipalId, storageBlobDataContributorRole)
  scope: storageAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: storageBlobDataContributorRole
    principalType: 'ServicePrincipal'
  }
}

// Project → Search
resource projectSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, projectPrincipalId, searchIndexDataReaderRole)
  scope: searchService
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: searchIndexDataReaderRole
    principalType: 'ServicePrincipal'
  }
}
