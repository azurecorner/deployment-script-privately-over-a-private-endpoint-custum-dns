https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-vnet-private-endpoint
https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-bicep?tabs=CLI




$templateFile='main-dns.bicep'
$resourceGroupName='RG-DEPLOYMENT-SCRIPT-DNS'
$deploymentName='deployment-001'
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name $deploymentName -TemplateFile $templateFile -DeploymentDebugLogLevel All