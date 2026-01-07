// security.bicep - DEPRECATED
//
// This module previously enabled Defender for Storage advanced settings as part of the core deployment.
// Defender enablement has been moved to an explicit post-deploy add-on to avoid accidental subscription-wide
// or resource-level security/billing changes during `azd up`.
//
// Use instead:
// - infra/addons/defender/storage-settings.bicep
// - scripts/enable-defender.sh

param storageAccountName string

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

// Note: Defender for AI enablement is not implemented here. Track status:
// https://github.com/matthansen0/azure-ai-security-sandbox/issues/14
