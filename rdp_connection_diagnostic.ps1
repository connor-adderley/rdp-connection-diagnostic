<#
.SYNOPSIS
    Diagnoses machine-side causes of remote desktop (RDP) connection failures on a shared PC.

.DESCRIPTION
    When a user reports they cannot connect to a shared remote PC over RDP, this script
    checks the machine-side conditions that can block a connection and reports each as a
    simple true/false result:

      - Whether the user is a member of the local "Remote Desktop Users" group
      - Whether the machine's concurrent-session limit has been reached by other users
      - Whether the user already holds an active (possibly hung) session
      - Whether RDP is enabled at the OS level
      - Whether the Remote Desktop Services service is running
      - Whether the machine is listening on the RDP port

    Where a fixable cause is found, a copy-paste remediation command is printed. The script
    is READ-ONLY: it diagnoses and suggests, but never changes anything itself.

    It must be run ON the target PC. A local script cannot see the network path between the
    user and the machine, so a healthy result rules out the machine, not the connection.

.PARAMETER Username
    The account to check. Accepts a bare name (jdoe), a down-level name (DOMAIN\jdoe),
    or a UPN (jdoe@example.com); all are reduced to the bare account name internally.

.PARAMETER MaxSessions
    The maximum number of concurrent sessions the machine is expected to support.
    Defaults to 2. Used to decide whether capacity has been reached.

.PARAMETER DomainPrefix
    The domain/join prefix used when building the group-add remediation command.
    Defaults to "AzureAD" for Entra-joined devices.

.PARAMETER RdpPort
    The TCP port to check for an RDP listener. Defaults to 3389.

.EXAMPLE
    .\remote_pc_check.ps1 -Username jdoe

    Runs all checks for user "jdoe" using the default two-session limit and RDP port 3389.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\remote_pc_check.ps1 -Username DOMAIN\jdoe

    Typical invocation from a remote management console where the script execution policy
    may otherwise block it.

.EXAMPLE
    .\remote_pc_check.ps1 -Username jdoe -MaxSessions 3 -DomainPrefix CONTOSO

    Checks against a three-session limit and builds the group-add command for an
    on-premises domain named CONTOSO.

.OUTPUTS
    A formatted list of the check results, followed by a "Suggested remediation" block
    listing any fixable causes found. The remediation block is omitted entirely when no
    fixable cause is detected.

.NOTES
    Author  : Connor Adderley
    Version : 1.0
    Requires: PowerShell 5.1+ and local administrator rights.

    Known limitations:
      - Checks machine-side causes only; cannot see the user-to-PC network path (VPN,
        routing, firewalls in between). Confirm those separately.
      - Capacity counts ACTIVE sessions only; a disconnected session still holds a slot
        until it times out or is logged off.
      - quser truncates very long usernames, which may affect matching in edge cases.
      - The group-add remediation assumes the account resolves under the given prefix;
        SID-resolution issues may require adding by object ID instead.
#>

param (
    [Parameter(Mandatory=$true)][string]$Username,
    [int]$MaxSessions = 2,
    [string]$DomainPrefix = "AzureAD",
    [int]$RdpPort = 3389
)

# Normalise input to a bare account name (accepts DOMAIN\user or user@domain)
$User = $Username
if ($User -match '\\') { $User = ($User -split '\\')[-1] }
if ($User -match '@')  { $User = ($User -split '@')[0] }

$Results = [ordered]@{
    TargetUser           = $User
    InRdpGroup           = $false
    CapacityReached      = $false   # TRUE = all slots taken, no room for a new session
    UserHasActiveSession = $false
    RdpEnabled           = $false
    ServiceRunning       = $false
    PortListening        = $false
}

# STEP 1 — Remote Desktop Users group membership
$GroupMembers = Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue
$Results.InRdpGroup = [bool]($GroupMembers | Where-Object { ($_.Name -split '\\')[-1] -eq $User })

# STEP 2 & 3 — Session checks
$Sessions = quser 2>$null | Select-Object -Skip 1 | ForEach-Object {
    if ($_ -match '^\s*>?\s*(\S+)\s+(?:(\S+)\s+)?(\d+)\s+(\w+)') {
        [PSCustomObject]@{ Username=$Matches[1]; ID=$Matches[3]; State=$Matches[4] }
    }
}

# Count other users' active sessions to decide capacity (not displayed)
$OtherActiveCount = ($Sessions | Where-Object { $_.State -eq 'Active' -and $_.Username -ne $User } | Measure-Object).Count
$Results.CapacityReached = ($OtherActiveCount -ge $MaxSessions)

$UserActive = $Sessions | Where-Object { $_.State -eq 'Active' -and $_.Username -eq $User }
$Results.UserHasActiveSession = [bool]$UserActive

# Only add UserSessionID to the output if the user actually has an active session
if ($UserActive) {
    $idx = [array]::IndexOf(@($Results.Keys), 'UserHasActiveSession') + 1
    $Results.Insert($idx, 'UserSessionID', $UserActive.ID)
}

# STEP 4 — RDP enabled in system settings (0 = allowed, 1 = denied)
$DenyRDP = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
$Results.RdpEnabled = ($DenyRDP -eq 0)

# STEP 5 — Service running and listening on the RDP port
$Results.ServiceRunning = (Get-Service TermService -ErrorAction SilentlyContinue).Status -eq 'Running'
$Results.PortListening  = [bool](Get-NetTCPConnection -LocalPort $RdpPort -State Listen -ErrorAction SilentlyContinue)

# Build remediation suggestions based on the results
$Suggestions = @()

if (-not $Results.InRdpGroup) {
    $Suggestions += "User is NOT in the Remote Desktop Users group. Add them with:"
    $Suggestions += "    net localgroup `"Remote Desktop Users`" $DomainPrefix\$User /add"
}
if ($Results.CapacityReached) {
    $Suggestions += "Session limit reached ($MaxSessions max). Wait for another user to log off before this user can connect."
}
if ($Results.UserHasActiveSession) {
    $Suggestions += "User already has an active session (possibly hung). End it with:"
    $Suggestions += "    logoff $($UserActive.ID)"
}

# Output: results first, then any suggestions
([PSCustomObject]$Results | Format-List | Out-String).TrimEnd()

if ($Suggestions.Count) {
    "`n=== Suggested remediation ==="
    $Suggestions -join "`n"
}
