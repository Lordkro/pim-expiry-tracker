# Grant Graph Permissions to PIM Expiry Tracker Managed Identity
# Run this AFTER deploying the Bicep template (requires Global Admin or appropriate role)

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ManagedIdentityPrincipalId,

    [Parameter(Mandatory=$false)]
    [string]$TenantId
)

# Connect to Microsoft Graph (needs Admin consent to assign permissions)
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes 'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All'

# Get the Microsoft Graph service principal (the API)
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
if (-not $graphSp) {
    throw "Could not find Microsoft Graph service principal"
}

# Get the service principal for our Managed Identity
$miSp = Get-MgServicePrincipal -ServicePrincipalId $ManagedIdentityPrincipalId
if (-not $miSp) {
    throw "Could not find Managed Identity service principal with ID $ManagedIdentityPrincipalId"
}

# Define required permissions (delegated or application? For MI we use application permissions)
$requiredPermissions = @(
    'User.Read.All',
    'RoleManagement.Read.All'
)

foreach ($permName in $requiredPermissions) {
    # Find the app role (permission) on Microsoft Graph
    $appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq $permName -and $_.AllowedMemberTypes -contains 'Application' }
    if (-not $appRole) {
        Write-Warning "Permission $permName not found as application permission on Microsoft Graph"
        continue
    }

    # Check if already assigned
    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miSp.Id -Filter "appRoleId eq '$($appRole.Id)'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "$permName already assigned" -ForegroundColor Green
        continue
    }

    # Create app role assignment
    Write-Host "Assigning $permName to Managed Identity..." -ForegroundColor Yellow
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miSp.Id -PrincipalId $miSp.Id -ResourceId $graphSp.Id -AppRoleId $appRole.Id | Out-Null
    Write-Host "✅ $permName assigned" -ForegroundColor Green
}

Write-Host "`nAll permissions assigned. Note: Some permissions may require admin consent in Azure AD. If any errors, ensure you are a Global Admin." -ForegroundColor Cyan

# Disconnect
Disconnect-MgGraph
