param([string] $name, [string] $subscription)
$output = 'Hello {0}' -f $name
#Write-Output $output

Connect-AzAccount -UseDeviceAuthentication
Set-AzContext -subscription $subscription

$kv = Get-AzKeyVault
#Write-Output $kv

$DeploymentScriptOutputs = @{}
$DeploymentScriptOutputs['greeting'] = $output
$DeploymentScriptOutputs['kv'] = $kv.resourceId
Write-Output $DeploymentScriptOutputs