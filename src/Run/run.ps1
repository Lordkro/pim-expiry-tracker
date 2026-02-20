# PIM Expiry Tracker — Azure Function (PowerShell)
# Queries Microsoft Graph for eligible PIM roles that expire within threshold.
# Publishes results to Event Grid via output binding.

param(
    $Timer   # Timer trigger input
)

#region Config
$thresholdDays    = [int]($env:ThresholdDays -as [int] ?? 30)
$nowUtc           = [datetime]::UtcNow
#endregion

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message"
}

try {
    Write-Log "PIM Expiry Tracker started (threshold: $thresholdDays days)"

    #region Connect to Microsoft Graph
    Write-Log "Connecting to Microsoft Graph with Managed Identity..."
    Connect-MgGraph -Identity -NoWelcome | Out-Null
    #endregion

    #region Fetch users
    Write-Log "Fetching all users..."
    $users = Get-MgUser -All -Property Id, UserPrincipalName
    $userLookup = @{}
    foreach ($u in $users) {
        if ($u.Id -and $u.UserPrincipalName) {
            $userLookup[$u.Id] = $u.UserPrincipalName
        }
    }
    Write-Log "Fetched $($userLookup.Count) users"
    #endregion

    #region Fetch PIM eligible assignments (beta API)
    Write-Log "Fetching role eligibility instances..."
    $allEligibleAssignments = [System.Collections.Generic.List[object]]::new()
    $uri = '/beta/roleManagement/directory/roleEligibilityScheduleInstances'
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        foreach ($item in $response.value) {
            $allEligibleAssignments.Add($item)
        }
        $uri = $response.'@odata.nextLink'
    } while ($uri)
    Write-Log "Fetched $($allEligibleAssignments.Count) eligible assignments"
    #endregion

    #region Fetch role definitions
    Write-Log "Fetching role definitions..."
    $roleDefinitions = Get-MgRoleManagementDirectoryRoleDefinition -All
    $roleLookup = @{}
    foreach ($role in $roleDefinitions) {
        $roleLookup[$role.Id] = $role.DisplayName
    }
    Write-Log "Fetched $($roleLookup.Count) role definitions"
    #endregion

    #region Process and filter assignments
    $expiringSoon = foreach ($assignment in $allEligibleAssignments) {
        if (-not $assignment.endDateTime) { continue }

        $endUtc       = ([datetimeoffset]$assignment.endDateTime).UtcDateTime
        $daysRemaining = [math]::Floor(($endUtc - $nowUtc).TotalDays)

        if ($daysRemaining -ge $thresholdDays) { continue }

        [pscustomobject]@{
            CollectedAt       = $nowUtc.ToString('o')
            UserPrincipalName = $userLookup[$assignment.principalId] ?? $assignment.principalId
            RoleName          = $roleLookup[$assignment.roleDefinitionId] ?? $assignment.roleDefinitionId
            AssignmentId      = $assignment.id
            EndDateTime       = $endUtc.ToString('o')
            DaysRemaining     = $daysRemaining
        }
    }

    if (-not $expiringSoon -or @($expiringSoon).Count -eq 0) {
        Write-Log "No expiring PIM eligibilities found within $thresholdDays days"
        return
    }

    $count = @($expiringSoon).Count
    Write-Log "Found $count expiring assignment(s). Publishing to Event Grid..."
    #endregion

    #region Publish to Event Grid
    $events = foreach ($item in $expiringSoon) {
        [pscustomobject]@{
            id          = [guid]::NewGuid().ToString()
            eventType   = 'PimRoleExpiringSoon'
            subject     = "PIM Role Expiry: $($item.UserPrincipalName) - $($item.RoleName)"
            eventTime   = $nowUtc.ToString('o')
            data        = $item
            dataVersion = '1.0'
        }
    }

    Push-OutputBinding -Name EventGridOutput -Value $events
    Write-Log "Successfully published $count event(s) to Event Grid"
    #endregion
}
catch {
    Write-Log "ERROR: $_" -Level 'ERROR'
    throw
}
finally {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue } catch { }
}
