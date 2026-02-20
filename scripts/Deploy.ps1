# PIM Expiry Tracker — Deployment Script
# Creates resource group, deploys infrastructure via Bicep, and optionally publishes function code.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$Location = 'westeurope',

    [Parameter(Mandatory = $true)]
    [string]$FunctionAppName,

    [Parameter(Mandatory = $false)]
    [string]$ParametersFile = 'infra\parameters.json',

    [Parameter(Mandatory = $false)]
    [switch]$SkipCodeDeploy
)

$ErrorActionPreference = 'Stop'

# Validate prerequisites
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install from: https://aka.ms/cli"
}

if (-not (Test-Path $ParametersFile)) {
    throw "Parameters file not found: $ParametersFile. Copy infra\parameters.example.json to infra\parameters.json and customize."
}

# Create resource group (idempotent)
Write-Host "Ensuring resource group '$ResourceGroup' exists in '$Location'..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group" }

# Deploy infrastructure
$deploymentName = "pim-tracker-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Deploying infrastructure..." -ForegroundColor Cyan
az deployment group create `
    --resource-group $ResourceGroup `
    --name $deploymentName `
    --template-file infra\main.bicep `
    --parameters "@$ParametersFile" `
    --parameters functionAppName=$FunctionAppName location=$Location

if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed" }

# Fetch outputs
Write-Host "Fetching deployment outputs..." -ForegroundColor Cyan
$outputsJson = az deployment group show `
    --resource-group $ResourceGroup `
    --name $deploymentName `
    --query properties.outputs `
    -o json | ConvertFrom-Json

$principalId   = $outputsJson.managedIdentityPrincipalId.value
$topicEndpoint = $outputsJson.eventGridTopicEndpoint.value

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "Function App:                 $FunctionAppName"
Write-Host "Managed Identity Principal ID: $principalId"
Write-Host "Event Grid Topic Endpoint:     $topicEndpoint"

Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Grant Graph permissions (run as Global Admin):"
Write-Host "   .\scripts\Grant-GraphPermissions.ps1 -ManagedIdentityPrincipalId $principalId -TenantId <your-tenant-id>"

if (-not $SkipCodeDeploy) {
    Write-Host "2. Deploy function code:"
    Write-Host "   .\scripts\Publish-FunctionCode.ps1 -FunctionAppName $FunctionAppName -ResourceGroup $ResourceGroup"
}
