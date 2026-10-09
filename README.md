# Remote PC Connection Troubleshooting Script

An automated script intended for use by 1st line support to detect and resolve common causes of remote PC connection issues.

End users frequently report issues connecting to a set of remote PCs. This script has been designed to check for common causes of connection issues, and suggest a resolution if the cause is found. It facilitates first line investigation and resolution, reducing the time to resolution and the number of tickets requiring second line escalation.

## Requirements

- PowerShell 5.1+
- Remote connection to the remote PC with local administrator permissions
- Must run directly on the remote PC that the user reports they cannot access

## Usage

```powershell
.\rdp_connection_diagnostic.ps1 -Username [username]
```

`-Username` accepts a bare name, a `DOMAIN\user`, or a `user@domain` format.

**Optional parameters**

| Parameter | Default | Purpose |
|---|---|---|
| `-MaxSessions` | `2` | Maximum concurrent sessions the machine is expected to support. |
| `-DomainPrefix` | `AzureAD` | Join prefix used when building the group-add remediation command. Use the NetBIOS domain name for an on-premises domain. |
| `-RdpPort` | `3389` | TCP port checked for an RDP listener. |

```powershell
.\rdp_connection_diagnostic.ps1 -Username janedoe -MaxSessions 3 -DomainPrefix CONTOSO
```

## Output

| Field | Meaning |
|---|---|
| `TargetUser` | The user account being used for the queries. |
| `InRdpGroup` | Whether the user is in the local group required to enable RDP connections. |
| `CapacityReached` | Whether the concurrent-session limit (two by default) is fully occupied by other users. |
| `UserHasActiveSession` | Whether the target user already has an active session, which may indicate an unresponsive or hung session blocking sign in. |
| `RdpEnabled` | Whether RDP is enabled on the remote PC. |
| `ServiceRunning` | Whether the RDP service is running. |
| `PortListening` | Whether the RDP port is listening. |

If a cause is identified (e.g. the user is not in the correct local group), a remediation step is suggested. The script is **read only** — no remediation steps are carried out by the script itself, and the remediation block is omitted entirely when no fixable cause is found.

**Sample**

```text
TargetUser           : JaneDoe
InRdpGroup           : False
CapacityReached      : False
UserHasActiveSession : False
RdpEnabled           : True
ServiceRunning       : True
PortListening        : True

=== Suggested remediation ===
User is NOT in the Remote Desktop Users group. Add them with:
    net localgroup "Remote Desktop Users" AzureAD\JaneDoe /add
```

## Limitations

- Checks machine-side causes only. Cannot see the network path.
- quser truncates very long usernames, which may affect matching in edge cases.
- The group-add remediation assumes the account resolves under the given prefix. SID-resolution issues may require adding by object ID instead.
