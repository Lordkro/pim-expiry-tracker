# Publish PIM Expiry Tracker function code to Azure Function App

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FunctionAppName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'

# Validate prerequisites
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install from: https://aka.ms/cli"
}

# Resolve paths relative to repository root
$repoRoot = Split-Path $PSScriptRoot -Parent
$srcPath  = Join-Path $repoRoot 'src'
$zipPath  = Join-Path $repoRoot 'function.zip'

if (-not (Test-Path (Join-Path $srcPath 'host.json'))) {
    throw "Cannot find src\host.json — are you running from the repo root?"
}

# Clean previous zip
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Package function code
Write-Host "Packaging function code from src\..." -ForegroundColor Cyan
Push-Location $srcPath
try {
    Compress-Archive -Path .\* -DestinationPath $zipPath -Force
}
finally {
    Pop-Location
}

# Deploy
Write-Host "Deploying zip to Function App '$FunctionAppName'..." -ForegroundColor Cyan
az functionapp deployment source config-zip --resource-group $ResourceGroup --name $FunctionAppName --src $zipPath

if ($LASTEXITCODE -ne 0) { throw "Code deployment failed" }

Write-Host "Code deployed successfully!" -ForegroundColor Green
Write-Host "Function App URL: https://$FunctionAppName.azurewebsites.net"

# Clean up zip
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
