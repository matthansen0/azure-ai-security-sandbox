// role-assignments.bicep - RBAC role assignments for managed identity

param principalId string
param openAiAccountName string
param searchServiceName string
param storageAccountName string
param cosmosDbAccountName string

// Reference existing resources
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' existing = {
  name: openAiAccountName
}

resource searchService 'Microsoft.Search/searchServices@2024-03-01-preview' existing = {
  name: searchServiceName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosDbAccountName
}

// Role definitions
var cognitiveServicesOpenAIUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
var searchIndexDataContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
var searchServiceContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
var storageBlobDataContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var cosmosDbDataContributorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002')

// OpenAI - Cognitive Services OpenAI User
resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, principalId, cognitiveServicesOpenAIUserRole)
  scope: openAiAccount
  properties: {
    roleDefinitionId: cognitiveServicesOpenAIUserRole
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Search - Index Data Contributor
resource searchIndexRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, principalId, searchIndexDataContributorRole)
  scope: searchService
  properties: {
    roleDefinitionId: searchIndexDataContributorRole
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Search - Service Contributor (for creating indexes)
resource searchServiceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, principalId, searchServiceContributorRole)
  scope: searchService
  properties: {
    roleDefinitionId: searchServiceContributorRole
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage - Blob Data Contributor
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, storageBlobDataContributorRole)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRole
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Cosmos DB - Data Contributor (built-in role)
// Note: Cosmos DB uses its own RBAC system, this creates a SQL role assignment
resource cosmosDbSqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosDbAccount
  name: guid(cosmosDbAccount.id, principalId, 'cosmos-data-contributor')
  properties: {
    roleDefinitionId: '${cosmosDbAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    principalId: principalId
    scope: cosmosDbAccount.id
  }
}
