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
