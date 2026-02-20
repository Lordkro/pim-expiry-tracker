# Grant Graph Permissions to PIM Expiry Tracker Managed Identity
# Run this AFTER deploying the Bicep template.
# Requires Global Admin or Privileged Role Administrator.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManagedIdentityPrincipalId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

$ErrorActionPreference = 'Stop'

# Connect to Microsoft Graph with required scopes
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
$connectParams = @{ Scopes = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All') }
if ($TenantId) { $connectParams.TenantId = $TenantId }
Connect-MgGraph @connectParams

# Get the Microsoft Graph service principal
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
if (-not $graphSp) {
    throw "Could not find Microsoft Graph service principal"
}

# Get the Managed Identity service principal
$miSp = Get-MgServicePrincipal -ServicePrincipalId $ManagedIdentityPrincipalId
if (-not $miSp) {
    throw "Could not find Managed Identity service principal with ID $ManagedIdentityPrincipalId"
}

# Required application permissions
$requiredPermissions = @(
    'User.Read.All',
    'RoleManagement.Read.All'
)

# Fetch existing assignments once (filter client-side for reliability)
$existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miSp.Id -All

foreach ($permName in $requiredPermissions) {
    # Find the app role on Microsoft Graph
    $appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq $permName -and $_.AllowedMemberTypes -contains 'Application' }
    if (-not $appRole) {
        Write-Warning "Permission '$permName' not found as application permission on Microsoft Graph — skipping"
        continue
    }

    # Check if already assigned
    $alreadyAssigned = $existingAssignments | Where-Object { $_.AppRoleId -eq $appRole.Id }

    if ($alreadyAssigned) {
        Write-Host "$permName — already assigned" -ForegroundColor Green
        continue
    }

    # Assign the app role
    Write-Host "Assigning $permName to Managed Identity..." -ForegroundColor Yellow
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $miSp.Id `
        -PrincipalId $miSp.Id `
        -ResourceId $graphSp.Id `
        -AppRoleId $appRole.Id | Out-Null

    Write-Host "$permName — assigned" -ForegroundColor Green
}

Write-Host "`nAll permissions assigned. Permissions may take a few minutes to propagate." -ForegroundColor Cyan

Disconnect-MgGraph
