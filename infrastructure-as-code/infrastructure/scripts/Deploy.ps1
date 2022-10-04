param(
    [Parameter(Mandatory)] [string] [ValidateSet("dev", "qa", "prod", "sandbox")] $Environment,
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $Location,
    [Parameter(Mandatory)] [string] $SolutionName,
    [string] $SolutionParametersFile = "./infrastructure-as-code/infrastructure/parameters/parameters.$Environment.json",
    [string] $DeploymentOutputFile
)

$ErrorActionPreference = "Stop"

[string] $TemplateSpecRgName = "rg-$SolutionName-template-specs"

Write-Host "Start deploying $SolutionName for $Version at $Location" -ForegroundColor Green

Write-Host "Getting template spec $TemplateSpecRgName $Version..." -ForegroundColor Green
$template = Get-AzTemplateSpec -ResourceGroupName $TemplateSpecRgName -Name $SolutionName -Version $Version

Write-Host "Deploying template..." -ForegroundColor Green
$deployment = New-AzDeployment -Location $Location -TemplateSpecId $template.Versions.Id -Name $Version `
                -TemplateParameterFile $SolutionParametersFile -SkipTemplateParameterPrompt -Verbose

if ($DeploymentOutputFile) {
    Write-Host "Saving outputs to $DeploymentOutputFile..." -ForegroundColor Green
    $clustersOutput = @{}
    foreach ($output in $Deployment.Outputs.GetEnumerator()) {
        $clustersOutput.Add($output.Key, $output.Value.Value) 
    }
    $clustersOutput | ConvertTo-Json | Set-Content -Path $DeploymentOutputFile
}
