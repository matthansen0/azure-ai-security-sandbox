// container-registry.bicep - Azure Container Registry for image builds

param name string
param location string = resourceGroup().location
param tags object = {}

param adminUserEnabled bool = true  // Needed for Container Apps to pull images
param sku object = {
  name: 'Standard'
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: sku
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: 'Enabled'
  }
}

output loginServer string = containerRegistry.properties.loginServer
output name string = containerRegistry.name
output resourceId string = containerRegistry.id
