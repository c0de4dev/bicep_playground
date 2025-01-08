param vnetName string
param addressPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
    name: vnetName
    location: resourceGroup().location
    properties: {
        addressSpace: {
            addressPrefixes: [
                addressPrefix
            ]
        }
    }
}
