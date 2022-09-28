Using module ./Common.psm1
Using module ./AzureDevOps.psm1
Using module ./Logging.psm1

function SetupServicePrincipals
{
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)] [hashtable] $Configuration
    )

	BeginScope -Scope "Service Principals"

    $servicePrincipals = @{}

    foreach ($principalName in $Configuration.servicePrincipals)
	{
		$servicePrincipal = CreateOrGetServicePrincipal -Name $principalName

        $servicePrincipals += @{        
            $servicePrincipal.DisplayName = @{
                "objectId" = $servicePrincipal.Id
                "clientId" = $servicePrincipal.AppId
                "displayName" = $servicePrincipal.DisplayName
                "clientSecret" = $servicePrincipal.PasswordCredentials.SecretText
            }
        }

    }

	EndScope
	
    return $servicePrincipals
}

function CreateOrGetServicePrincipal
{
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)] [string] $Name
    )

    LogInfo -Message "Trying to get Service principal '$Name'."

	$servicePrincipal = Get-AzADServicePrincipal -DisplayName $Name

	if (! $servicePrincipal)
	{ 
		$servicePrincipal = New-AzADServicePrincipal -DisplayName $Name
		LogInfo -Message "Service principal '$Name' created."
	}
	else
	{
		LogWarning -Message "Service principal $Name' already exists."
	}

	return $servicePrincipal
}

function SetupEnvironments {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)] [hashtable] $Configuration,
        [Parameter(Mandatory)] [hashtable] $ServicePrincipals
    )

    foreach ($envKey in $Configuration.environments.keys) 
	{
		BeginScope -Scope "Environment: $envKey"
		
		$enviroment = $Configuration.environments[$envKey]
		
        #Only one item in array
        $servicePrincipal = $ServicePrincipals[$Configuration.servicePrincipals[0]]

        Set-AzContext -Subscription $enviroment.subscriptionId

        AssignRoleIfNotExists -RoleName "Owner" -ObjectId $servicePrincipal.objectId -SubscriptionId $enviroment.subscriptionId
        AssignApplicationAdministratorAZRole -ObjectId $servicePrincipal.objectId

        SetupResourceGroups -Environment $envKey -Configuration $Configuration
		SetupServiceConnection -Environment $enviroment -ServicePrincipal $servicePrincipal -Configuration $Configuration

		EndScope
	}
}

function SetupResourceGroups {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)] [string] $Environment,
        [Parameter(Mandatory)] [hashtable] $Configuration
    )

    foreach ($resourceType in @('data','compute','ml','network')) 
	{
		$SolutionName =	$Configuration.project.alias
		CreateOrGetResourceGroup `
			-Name "rg-$SolutionName-$resourceType-$Environment" `
			-Location $Configuration.project.location
	}

	CreateOrGetResourceGroup `
		-Name "rg-$SolutionName-template-specs" `
		-Location $Configuration.project.location

}

function CreateOrGetResourceGroup 
{
    [cmdletbinding()]
	[OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Location
    )

    $resourceGroup = Get-AzResourceGroup -Name $Name -ErrorAction Ignore

    if (!$resourceGroup)
	{
        $resourceGroup = New-AzResourceGroup -Name $Name -Location $Location
		LogInfo -Message "Resource group '$Name' created."
    }
    else 
    {
		LogWarning -Message "Resource group '$Name' already exists."
    }

	return $resourceGroup
}

function AssignApplicationAdministratorAZRole
{
    [cmdletbinding()]
	[OutputType([void])]
    param (
        [Parameter(Mandatory)] [string] $ObjectId
    )

    # Login into Azure AD with current user
    # Connect-AzureAD

    # Fetch role instance
    $role = Get-AzureADDirectoryRole | Where-Object {$_.displayName -eq 'Application administrator'}

    # If role instance does not exist, instantiate it based on the role template
    if ($role -eq $null) {
        # Instantiate an instance of the role template
        $roleTemplate = Get-AzureADDirectoryRoleTemplate | Where-Object {$_.displayName -eq 'Application Administrator'}
        Enable-AzureADDirectoryRole -RoleTemplateId $roleTemplate.ObjectId

        # Fetch role
        $role = Get-AzureADDirectoryRole | Where-Object {$_.displayName -eq 'Application Administrator'}
    }

    # Add the SP to role
    try {
        Add-AzureADDirectoryRoleMember -ObjectId $role.ObjectId  -RefObjectId $ObjectId
        LogInfo -Message "Service Principal add into Role Application administrator with success!"
    }
    catch { 
        LogInfo -Message "Service Principal already have Application administrator role."
    }
    
}

function AssignRoleIfNotExists 
{
    [cmdletbinding()]
	[OutputType([void])]
    param (
        [Parameter(Mandatory)] [string] $RoleName,
        [Parameter(Mandatory)] [string] $ObjectId,
        [Parameter(Mandatory)] [string] $SubscriptionId
    )

    $scope = "/subscriptions/$SubscriptionId"
    $roleAssignment = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $scope

    if (! $roleAssignment)
    {	
        # Remove retry loop after https://github.com/Azure/azure-powershell/issues/2286 is fixed
        $totalRetries = 30
        $retryCount = $totalRetries
        While ($True) {
            Try {
                New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $scope
                break
            }
            Catch {
                If ($retryCount -eq 0) {
                    LogError -Message "An error occurred: $($_.Exception)`n$($_.ScriptStackTrace)"
                    throw "The principal '$ObjectId' cannot be granted '$RoleName' role on the subscription '$SubscriptionId'. Please make sure the principal exists and try again later."
                }
                $retryCount--
                LogWarning -Message "The principal '$ObjectId' cannot be granted '$RoleName' role on the subscription '$SubscriptionId'. Trying again (attempt $($totalRetries - $retryCount)/$totalRetries)"
                Start-Sleep 10
            }
        }
        LogInfo -Message "Role '$RoleName' assigned to principal '$ObjectId' on the subscription '$SubscriptionId'."
    }
    else
    {
        LogWarning -Message "Role '$RoleName' was already assigned to principal '$ObjectId' oon the subscription '$SubscriptionId'."
    }
}
