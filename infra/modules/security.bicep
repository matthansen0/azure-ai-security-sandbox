// security.bicep - Resource-level security configurations

param storageAccountName string
param logAnalyticsWorkspaceId string

// Reference the storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Defender for Storage with advanced settings
resource defenderForStorage 'Microsoft.Security/defenderForStorageSettings@2022-12-01-preview' = {
  name: 'current'
  scope: storageAccount
  properties: {
    isEnabled: true
    overrideSubscriptionLevelSettings: true
    malwareScanning: {
      onUpload: {
        isEnabled: true
        capGBPerMonth: 5000 // 5TB cap per month
      }
    }
    sensitiveDataDiscovery: {
      isEnabled: true
    }
  }
}

// Note: Defender for AI is configured at the subscription level via workspace settings
// The Log Analytics workspace is used to collect Defender for AI alerts
// This is handled by the security workspace setting in subscription-security.bicep
