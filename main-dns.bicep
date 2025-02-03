@description('Specify a project name that is used for generating resource names.')
param projectName string='datasynchro'

@description('Specify the resource location.')
param location string = resourceGroup().location

@description('Specify the container image.')
param containerImage string = 'mcr.microsoft.com/azuredeploymentscripts-powershell:az9.7'

@description('Specify the mount path.')
param mountPath string = '/mnt/azscripts/azscriptinput'

var storageAccountName = toLower('${projectName}store')
var fileShareName = '${projectName}share'
var containerGroupName = '${projectName}cg'
var containerName = '${projectName}container'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccountName}/default/${fileShareName}'
  dependsOn: [
    storageAccount
  ]
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  properties: {

    subnetIds: [
      {
        id: virtualNetwork::containerInstanceSubnet.id
      }
    ]
    containers: [
      {
        name: containerName
        properties: {
          image: containerImage
          resources: {
            requests: {
              cpu: 1
              memoryInGB: json('1.5')
            }
          }
          ports: [
            {
              protocol: 'TCP'
              port: 80
            }
          ]
          volumeMounts: [
            {
              name: 'filesharevolume'
              mountPath: mountPath
            }
          ]
          command: [
            '/bin/sh'
            '-c'
            'pwsh -c \'Start-Sleep -Seconds 1800\''
          ]
        }
      }
    ]
    dnsConfig: {
      nameServers: [
        '10.221.2.4'
      ]
    }
    osType: 'Linux'
    volumes: [
      {
        name: 'filesharevolume'
        azureFile: {
          readOnly: false
          shareName: fileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
  }
}


resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'container-dns-vnet'
  location: location
  properties:{
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }

  resource privateEndpointSubnet 'subnets' = {
    name: 'PrivateEndpointSubnet'
    properties: {
      addressPrefixes: [
        '10.0.1.0/24'
      ]
    }
  }

  resource containerInstanceSubnet 'subnets' = {
    name: 'ContainerInstanceSubnet'
    properties: {
      addressPrefix: '10.0.2.0/24'
      delegations: [
        {
          name: 'containerDelegation'
          properties: {
            serviceName: 'Microsoft.ContainerInstance/containerGroups'
          }
        }
      ]
    }
  }
}

// https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-bicep-configure-dev

// https://learn.microsoft.com/en-us/azure/container-instances/container-instances-custom-dns
