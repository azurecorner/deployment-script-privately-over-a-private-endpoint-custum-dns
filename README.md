# Run Deployment Script Privately in Azure Over Private Endpoint and Custom DNS Server Using Bicep


## 1. Overview
Azure Deployment Scripts allow you to run PowerShell or Azure CLI scripts during a Bicep deployment. This is useful for tasks like configuring resources, retrieving values, or executing custom logic.  
[Learn more about Deployment Scripts in Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-bicep?tabs=CLI)

In my previous tutorial, I provided an introduction to Azure deployment scripts: Run Script in Azure Using Deployment Scripts and Bicep (https://logcorner.com/run-script-in-azure-using-deployment-scripts-and-bicep/)


The deployment script service requires both a Storage Account and an Azure Container Instance.

In a private environment, you can use an existing Storage Account with a private endpoint enabled. However, a deployment script requires a new Azure Container Instance and cannot use an existing one.

For more details on running a Bicep deployment script privately over a private endpoint, refer to this article: Run Bicep Deployment Script Privately (https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-vnet-private-endpoint).

In the article linked above, the Azure Container Instance resource is created automatically by the deployment script. But what happens if you use a custom DNS server? The limitation is that you cannot use a custom DNS server because the ACI is created automatically, and the only configurable option is the container group name.

In this tutorial, I will demonstrate how to use a custom DNS server to run a script in Azure.

---
To run deployment scripts privately, you need the following infrastructure:

- **A virtual network with two subnets:**
  - One subnet for the private endpoint.
  - One subnet for the Azure Container Instance (ACI) with **Microsoft.ContainerInstance/containerGroups** delegation.

- **A storage account** with public network access disabled.

- **A private endpoint** within the virtual network, configured with the **file** sub-resource on the storage account.

- **A private DNS zone** (`privatelink.file.core.windows.net`) linked to the created virtual network.

- **An Azure Container Group** attached to the ACI subnet, with a volume linked to the storage account file share.

- **A user-assigned managed identity** with **Storage File Data Privileged Contributor** permissions on the storage account, specified in the **identity** property of the container group resource.


---

## 3. Infrastructure
```bicep
/*  ------------------------------------------ Virtual Network ------------------------------------------ */
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

/*  ------------------------------------------ Private DNS Zone ------------------------------------------ */
resource privateStorageFileDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.core.windows.net'
  location: 'global'

  resource virtualNetworkLink 'virtualNetworkLinks' = {
    name: uniqueString(virtualNetwork.name)
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: virtualNetwork.id
      }
    }
  }


}

/*  ------------------------------------------ Managed Identity ------------------------------------------ */
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
}

```

## 3. Use an Existing Storage Account  




```bicep
/*  ------------------------------------------ Storage Account ------------------------------------------ */

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

/*  ------------------------------------------ File Share  ------------------------------------------ */

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccountName}/default/${fileShareName}'
  dependsOn: [
    storageAccount
  ]
}

```
## 4. Configure role assignement

```bicep
/*  ------------------------------------------ Role Assignment ------------------------------------------ */
resource storageFileDataPrivilegedContributorReference 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: roleNameStorageFileDataPrivilegedContributor
  scope: tenant()
}


resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageFileDataPrivilegedContributorReference.id, managedIdentity.id, storageAccount.id)
  scope: storageAccount
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: storageFileDataPrivilegedContributorReference.id
    principalType: 'ServicePrincipal'
  }
}


``` 
## 4. Configure private endpoint

```bicep

/*  ------------------------------------------ Private Endpoint ------------------------------------------ */
resource privateEndpointStorageFile 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${storageAccount.name}'
  location: location
  properties: {
   privateLinkServiceConnections: [
     {
       name: storageAccount.name
       properties: {
         privateLinkServiceId: storageAccount.id
         groupIds: [
           'file'
         ]
       }
     }
   ]
   customNetworkInterfaceName: '${storageAccount.name}-nic'
   subnet: {
     id: virtualNetwork::privateEndpointSubnet.id
   }
  }
}

/*  ------------------------------------------- private dns zone group  ------------------------------------------ */
resource privateEndpointStorageFilePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = {
  parent: privateEndpointStorageFile
  name: 'filePrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageFileDnsZone.id
        }
      }
    ]
  }
}

``` 
## 4. Configure a Container Instance  

```bicep

/*  ------------------------------------------ Contianer Group ------------------------------------------ */
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}' : {}
    }
  }
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
            'cd /mnt/azscripts/azscriptinput && [ -f hello.ps1 ] && pwsh ./hello.ps1 || echo "File (hello.ps1) not found, please upload file (hello.ps1) in storage account (datasynchrostore) fileshare (datasynchroshare) and restart the container "; pwsh -c "Start-Sleep -Seconds 1800"'
          ] 
          
        }
      }
    ]
   
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

```

---

### 2. Bicep Code   

```bicep

param deploymentScriptName string = 'inlinePS'
param location string = resourceGroup().location

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: deploymentScriptName
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '10.0'
    
    scriptContent: '''
      Write-Host 'Hello World'
      $output = 'Hello world from inline script'
      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['text'] = $output
    '''
    retentionInterval: 'PT1H'
  }
}

output result string = deploymentScript.properties.outputs.text
```

### Explanation of Each Component  

#### 1. Parameters  
- **`deploymentScriptName`** – Specifies the name of the deployment script (`inlinePS`).  
- **`location`** – Uses the resource group’s location to deploy the script.  

---

#### 2. Deployment Script Resource  
This defines a **`Microsoft.Resources/deploymentScripts`** resource that executes an **Azure PowerShell script**.  

- **`kind: 'AzurePowerShell'`** – Specifies that the script will run using Azure PowerShell.  
- **`azPowerShellVersion: '10.0'`** – Sets the PowerShell version to **10.0**.  
- **`scriptContent`** – Contains the actual PowerShell script:  
  - **`Write-Host 'Hello World'`** – Prints `"Hello World"` to the console.  
  - **Creates a dictionary (`$DeploymentScriptOutputs`)** to store output values.  
  - **Stores the text `"Hello world from inline script"`** as an output.  

---

#### 3. Retention Interval  
- **`retentionInterval: 'PT1H'`** – Keeps the script execution logs for **1 hour** before automatic cleanup.  

---

#### 4. Output Variable  
The script outputs the `text` value, which is retrieved using:  

```bicep
output result string = deploymentScript.properties.outputs.text
```

### Deploying an Inline Script Using Bicep  


This example demonstrates how to deploy an **inline Bicep script** using **Azure CLI** and **PowerShell**. The script creates a resource group and deploys the Bicep template within it.  

---

### Deployment Commands  

```powershell
$templateFile = 'inline-script.bicep' 
$resourceGroupName = 'RG-DEPLOYMENT-SCRIPT-GETTING-STARTED'
$deploymentName = 'deployment-$resourceGroupName'

# Create a resource group
az group create -l westus -n $resourceGroupName 

# Deploy the Bicep template
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -DeploymentDebugLogLevel All  
```

## 5. Monitoring

During the deployment of the deployment script, we can observe the following resources listed in the resource group:

A storage account
A container instance
The deployment script


![test1](https://github.com/user-attachments/assets/5aaa5490-a148-4c9f-b039-898e895f38d9)

Additionally, we can also view the deployment script logs.

![408822783-50013ad5-4882-49fa-a654-5ab82b42fafb](https://github.com/user-attachments/assets/a208c284-4e96-436f-aa45-8a870abd76c8)






















# ##################################################################################################################################

https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-vnet-private-endpoint
https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-bicep?tabs=CLI




$templateFile='main.bicep'
$resourceGroupName='RG-DEPLOYMENT-SCRIPT-DNS'
az group create -l westeurope -n $resourceGroupName
$deploymentName='deployment-001'
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name $deploymentName -TemplateFile $templateFile -DeploymentDebugLogLevel All


$containerName='datasynchrocg'
$resourceGroupName='RG-DEPLOYMENT-SCRIPT-DNS'

az container logs --resource-group $resourceGroupName --name $containerName

az container attach --resource-group $resourceGroupName --name $containerName

az container show --resource-group $resourceGroupName --name $containerName

az container exec --resource-group RG-DEPLOYMENT-SCRIPT-DNS --name datasynchrocg --exec-command "/bin/sh"
cd /mnt/azscripts/azscriptinput
pwsh ./hello.ps1
