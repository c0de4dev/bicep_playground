@description('Name of the resource group')
param rsgName string

@allowed([
  'eastus','eastus2','westus','westus2','northeurope','westeurope'
])
@description('Location for all resources.')
param location string


targetScope = 'subscription'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rsgName
  location: location
}
