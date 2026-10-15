# RDP Connection Diagnostic

A read-only PowerShell script for first-line support. It checks a remote PC for common causes of RDP connection and sign-in failures, and suggests a fix when it finds one.

Users of a shared pool of remote PCs often report that they cannot connect. The script checks the common machine-side causes, so first line can often resolve the issue without escalating to second line.

## Requirements

- PowerShell 5.1 or later
- Local administrator rights on the remote PC
- Script execution allowed by the PC's PowerShell execution policy

Run the script on the remote PC that the user cannot connect to, over your own remote connection to that PC.

## Usage

```powershell
.\rdp_connection_diagnostic.ps1 -Username janedoe
```

`-Username` accepts a bare name, `DOMAIN\user` or `user@domain`.

**Optional parameters**

| Parameter | Default | Purpose |
|---|---|---|
| `-MaxSessions` | `2` | Maximum number of concurrent sessions the PC is expected to support. |
| `-DomainPrefix` | `AzureAD` | Prefix used to build the suggested group-add command. Use the NetBIOS domain name for an on-premises domain. |
| `-RdpPort` | `3389` | TCP port checked for an RDP listener. |

```powershell
.\rdp_connection_diagnostic.ps1 -Username janedoe -MaxSessions 3 -DomainPrefix CONTOSO
```

## Output

| Field | Meaning |
|---|---|
| `TargetUser` | The user account the checks were run for. |
| `InRdpGroup` | Whether the user is in the local Remote Desktop Users group. |
| `CapacityReached` | Whether other users already occupy every concurrent session (`-MaxSessions`, default 2). |
| `UserHasActiveSession` | Whether the user already has an active session, which may be a hung session blocking sign-in. |
| `RdpEnabled` | Whether RDP is enabled on the PC. |
| `ServiceRunning` | Whether the RDP service is running. |
| `PortListening` | Whether the RDP port is listening. |

If the script finds a fixable cause, such as the user not being in the Remote Desktop Users group, it prints a suggested remediation command. The script is read-only. It makes no changes itself, and it leaves out the remediation block when it finds no fixable cause.

**Sample output**

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

- Checks machine-side causes only. It cannot see the network path between the user and the PC.
- `quser` truncates very long usernames, which can affect session matching in edge cases.
- The suggested group-add command assumes the account resolves under the given prefix. If SID resolution fails, add the account by object ID instead.

## Licence

MIT. See [LICENSE](LICENSE).
