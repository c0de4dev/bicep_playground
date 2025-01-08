param rsgName string = 'testbicep-rsg'
param location string = 'northeurope'

targetScope = 'subscription'
module rsg 'ResourceGroup/rsg.bicep' = {
  name: 'rsg'
  params: {
    rsgName: rsgName
    location: location
  }
}


module vnet 'VNET/vnet.bicep' = {
  scope: resourceGroup(rsgName)
  name: 'vnet'
  params: {
    vnetName: 'testbicep-vnet'
    addressPrefix: '10.0.0.0/16'
  }
}
