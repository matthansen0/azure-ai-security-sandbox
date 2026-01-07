// Add-on: Configure Defender for Storage advanced settings at the storage account scope
//
// IMPORTANT
// - This is still "Defender" configuration, but scoped to the specific storage account.
// - Intended to be run after `azd up` via scripts/enable-defender.sh.

targetScope = 'resourceGroup'

@description('Name of the Storage Account to configure.')
param storageAccountName string

@description('Enable Defender for Storage advanced settings on this storage account.')
param enableDefenderForStorageSettings bool = true

// Reference the storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource defenderForStorage 'Microsoft.Security/defenderForStorageSettings@2022-12-01-preview' = if (enableDefenderForStorageSettings) {
  name: 'current'
  scope: storageAccount
  properties: {
    isEnabled: true
    overrideSubscriptionLevelSettings: true
    malwareScanning: {
      onUpload: {
        isEnabled: true
        capGBPerMonth: 5000
      }
    }
    sensitiveDataDiscovery: {
      isEnabled: true
    }
  }
}

output defenderForStorageSettingsEnabled bool = enableDefenderForStorageSettings
