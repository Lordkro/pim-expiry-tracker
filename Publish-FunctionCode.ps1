# Publish PIM Expiry Tracker function code to Azure Function App

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup
)

# Check for Azure Functions Core Tools (optional)
$publishMethod = "az"

# Ensure we are in the PimExpiryTracker directory
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
if ((Get-Location).Path -notlike "*PimExpiryTracker*") {
    Set-Location $scriptDir
}

# Create zip package of function files
$zipPath = Join-Path $scriptDir "function.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }

Write-Host "Packaging function code..." -ForegroundColor Cyan
Compress-Archive -Path *.ps1, *.json, requirements.psd1 -DestinationPath $zipPath -Force

Write-Host "Deploying zip to Function App '$FunctionAppName'..." -ForegroundColor Cyan
az functionapp deployment source config-zip `
  --resource-group $ResourceGroup `
  --name $FunctionAppName `
  --src $zipPath

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Code deployed successfully!" -ForegroundColor Green
    Write-Host "Function App URL: https://$FunctionAppName.azurewebsites.net"
} else {
    throw "Code deployment failed"
}
