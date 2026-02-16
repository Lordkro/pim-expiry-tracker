# PIM Expiry Tracker — Azure Function (PowerShell)
# Queries Microsoft Graph for eligible PIM roles that expire within threshold
# Publishes results to Event Grid

using namespace System.Net

# Input bindings are passed in via param block
param(
    $Timer,               # Timer trigger
    $EventGridOutput      # Event Grid output binding (array of events)
)

#region Config
$thresholdDays = 30      # Days remaining threshold
$eventGridTopic = $env:EVENT_GRID_TOPIC_URL  # Set in Function App settings
#endregion

# Ensure Event Grid output is initialized
if (-not $EventGridOutput) {
    $EventGridOutput = @()
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message"
}

try {
    Write-Log "PIM Expiry Tracker started"

    # Connect to Microsoft Graph using Managed Identity
    Write-Log "Connecting to Microsoft Graph with Managed Identity..."
    Connect-MgGraph -Identity | Out-Null

    # Get all users (build lookup)
    Write-Log "Fetching all users..."
    $users = Get-MgUser -All -Property Id,UserPrincipalName
    $userLookup = @{}
    foreach ($u in $users) {
        if ($u.Id -and $u.UserPrincipalName) {
            $userLookup[$u.Id] = $u.UserPrincipalName
        }
    }
    Write-Log "Fetched $($userLookup.Count) users"

    # Get all role eligibility schedule instances (beta API)
    Write-Log "Fetching role eligibility instances..."
    $allEligibleAssignments = @()
    $uri = "/beta/roleManagement/directory/roleEligibilityScheduleInstances"
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $allEligibleAssignments += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)
    Write-Log "Fetched $($allEligibleAssignments.Count) eligible assignments"

    # Get role definitions lookup
    Write-Log "Fetching role definitions..."
    $roleDefinitions = Get-MgRoleManagementDirectoryRoleDefinition -All
    $roleLookup = @{}
    foreach ($role in $roleDefinitions) {
        $roleLookup[$role.Id] = $role.DisplayName
    }
    Write-Log "Fetched $($roleLookup.Count) role definitions"

    # Process assignments and calculate days remaining
    $nowUtc = [datetime]::UtcNow
    $processed = foreach ($assignment in $allEligibleAssignments) {
        $endUtc = $null
        $daysRemaining = $null

        if ($assignment.endDateTime) {
            $endUtc = ([datetimeoffset]$assignment.endDateTime).UtcDateTime
            $daysRemaining = [math]::Floor(($endUtc - $nowUtc).TotalDays)
        }

        [pscustomobject]@{
            CollectedAt       = $nowUtc.ToString('o')
            UserPrincipalName = $userLookup[$assignment.principalId]
            RoleName          = $roleLookup[$assignment.roleDefinitionId]
            AssignmentId      = $assignment.id
            EndDateTime       = $endUtc?.ToString('o')
            DaysRemaining     = $daysRemaining
        }
    }

    # Filter by threshold
    $expiringSoon = $processed | Where-Object {
        $_.DaysRemaining -ne $null -and $_.DaysRemaining -lt $thresholdDays
    }

    if (-not $expiringSoon -or $expiringSoon.Count -eq 0) {
        Write-Log "No expiring PIM eligibilities found (threshold: $thresholdDays days)"
        return
    }

    Write-Log "Found $($expiringSoon.Count) expiring assignments. Publishing to Event Grid..."

    # Build Event Grid events
    foreach ($item in $expiringSoon) {
        $event = [pscustomobject]@{
            id = [guid]::NewGuid().ToString()
            eventType = 'PimRoleExpiringSoon'
            subject = "PIM Role Expiry: $($item.UserPrincipalName) - $($item.RoleName)"
            eventTime = [datetime]::UtcNow.ToString('o')
            data = $item
            dataVersion = '1.0'
        }

        $EventGridOutput += $event
    }

    Write-Log "Successfully queued $($EventGridOutput.Count) events for Event Grid"
}
catch {
    Write-Log "ERROR: $_" -Level 'ERROR'
    throw $_  # Let Azure Function runtime handle the failure
}
finally {
    # Disconnect Graph to clean up context
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue } catch {}
}

# Output binding automatically sends $EventGridOutput array to Event Grid
