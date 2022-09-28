param (
    # Azure DevOps organization where you want to create this HOL resources
    [parameter(mandatory=$true)]
    [string]$orgName = '<orgName>',

    # Azure DevOps organization where you want to create this HOL resources
    [parameter(mandatory=$true)]
    [string]$projectName = '<projectName>',
    
    # ID of the Azure Subscription where you want to create this HOL resources
    [parameter(mandatory=$true)]
    [string]$subscriptionId = '<subscriptionId>',

    # ID of the Azure Subscription where you want to create this HOL resources
    [string]$configsTemplate = 'quickstart/scripts/cloud-setup/configs/template.json',

    # ID of the Azure Subscription where you want to create this HOL resources
    [string]$configsOutput = 'quickstart/scripts/cloud-setup/configs/hol.json'
)

$randomLetter = (65..90) + (97..122) | Get-Random -Count 1 | % {[char]$_} 
$gUUID = New-Guid
$projectAlias = $randomLetter + $gUUID.Guid.Split("-")[0].Substring(0, 7)
Write-Output "Project alias generated: " $projectAlias.ToLower()

(Get-Content $configsTemplate) `
    -replace '<projectName>', $projectName `
    -replace '<projectAlias>', $projectAlias.ToLower() `
    -replace '<orgName>', $orgName `
    -replace '<subscriptionId>', $subscriptionId |
  Out-File $configsOutput
