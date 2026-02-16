# PIM Expiry Tracker — Deployment Script
# Deploys infrastructure via Bicep and publishes function code

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$false)]
    [string]$Location = "westeurope",

    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName,

    [Parameter(Mandatory=$false)]
    [string]$ParametersFile = "parameters.json",

    [Parameter(Mandatory=$false)]
    [switch]$SkipCodeDeploy
)

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install from: https://aka.ms/cli"
}

# Ensure parameters file exists
if (-not (Test-Path $ParametersFile)) {
    throw "Parameters file not found: $ParametersFile. Copy parameters.example.json to parameters.json and customize."
}

$deploymentName = "pim-tracker-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "Deploying infrastructure..." -ForegroundColor Cyan
az deployment group create `
  --resource-group $ResourceGroup `
  --name $deploymentName `
  --template-file main.bicep `
  --parameters @$ParametersFile `
  --parameters functionAppName=$FunctionAppName location=$Location

if ($LASTEXITCODE -ne 0) {
    throw "Infrastructure deployment failed"
}

Write-Host "Fetching deployment outputs..." -ForegroundColor Cyan
$outputsJson = az deployment group show --resource-group $ResourceGroup --name $deploymentName --query properties.outputs -o json | ConvertFrom-Json
$principalId = $outputsJson.managedIdentityPrincipalId.value
$topicEndpoint = $outputsJson.eventGridTopicEndpoint.value

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "Function App: $FunctionAppName"
Write-Host "Managed Identity Principal ID: $principalId"
Write-Host "Event Grid Topic Endpoint: $topicEndpoint"
Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Grant Graph permissions (run as Global Admin):"
Write-Host "   .\Grant-GraphPermissions.ps1 -ManagedIdentityPrincipalId $principalId -TenantId <your-tenant-id>"
Write-Host "2. Deploy function code (skip if already done):"
if (-not $SkipCodeDeploy) {
    Write-Host "   .\Publish-FunctionCode.ps1 -FunctionAppName $FunctionAppName -ResourceGroup $ResourceGroup"
}
