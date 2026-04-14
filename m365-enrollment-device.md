# Device Enrollment — Full Method

```
╔═══════════════════════════════════════════════════════════════════╗
║  Entra Join + Intune MDM Enrollment — Single Device Procedure    ║
║  Result: Device managed in both Entra ID and Intune              ║
║  Policies, apps, compliance all flow automatically after this    ║
╚═══════════════════════════════════════════════════════════════════╝
```

---

## Prerequisites

- User has M365 E3 (or F3) license assigned
- MDM user scope set to All (or group containing user)
- User knows their work email (UPN) and password
- Device has internet access

---

## Step 1 — Check Current State

Run in elevated PowerShell:

```powershell
dsregcmd /status
```

| Output | Meaning | Action |
|:-------|:--------|:-------|
| `AzureAdJoined: YES` | Already joined | Skip to Step 4 |
| `WorkplaceJoined: YES` + `AzureAdJoined: NO` | Registered only, not joined | Go to Step 2 |
| Both NO | Not connected at all | Go to Step 3 |

---

## Step 2 — Remove Stale Workplace Registration

Only if `WorkplaceJoined: YES` and `AzureAdJoined: NO`.

```
Settings → Accounts → Access work or school → click existing account → Disconnect
```

Reboot. Then proceed to Step 3.

---

## Step 3 — Entra Join

```
Settings → Accounts → Access work or school → Connect → Join this device to Microsoft Entra ID
```

1. Enter user's work email (UPN)
2. Complete MFA if prompted
3. Confirm join
4. Sign out
5. At login screen, click **Other user**
6. Sign in with work email — **not** a local account

---

## Step 4 — Verify Entra Join

Run in PowerShell (no elevation needed):

```powershell
dsregcmd /status
```

**All four must be correct:**

```
AzureAdJoined      : YES
DeviceAuthStatus   : SUCCESS
AzureAdPrt         : YES
IsUserAzureAD      : YES
```

If `AzureAdPrt: NO` — user is signed in with a local account. Sign out and sign in with work email.

---

## Step 5 — Verify Intune MDM Enrollment

```powershell
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" | ForEach-Object {
    Get-ItemProperty $_.PSPath | Where-Object { $_.ProviderID -eq "MS DM Server" }
} | Select-Object ProviderID, UPN
```

| Output | Meaning | Action |
|:-------|:--------|:-------|
| Shows `MS DM Server` + UPN | Enrolled | Skip to Step 7 |
| Empty | MDM auto-enrollment failed | Go to Step 6 |

---

## Step 6 — Force MDM Enrollment

Only if Step 5 was empty.

```powershell
Start-Process "ms-device-enrollment:?mode=mdm"
```

A dialog opens. Enter the work email. If it shows **"We couldn't auto-discover a management endpoint"**, enter the MDM Server URL manually:

```
https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc
```

Complete the dialog. Re-run Step 5 to confirm `MS DM Server` appears.

---

## Step 7 — Verify in Portal

```
intune.microsoft.com → Devices → All devices → search for device name
```

Confirm:

- OS version populated
- Last check-in time is today
- Compliance state showing
- Managed by: Intune

---

## Step 8 — Fix Device Ownership

If device shows **Personal** instead of **Corporate** in the portal:

```
Click device name → Properties → change Ownership to Corporate → Save
```

---

## Step 9 — Force Policy Sync (Optional)

Speeds up initial policy delivery from hours to minutes:

```powershell
$enrollment = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" |
    Get-ItemProperty | Where-Object { $_.ProviderID -eq "MS DM Server" }

if ($enrollment) {
    $enrollID = Split-Path $enrollment.PSPath -Leaf
    Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\$enrollID\" | Start-ScheduledTask
    Write-Host "[OK] Intune sync triggered" -ForegroundColor Green
}
```

---

## Post-Enrollment State

| System | Status | What It Enables |
|:-------|:-------|:----------------|
| **Entra ID** | Joined | Identity, PRT, Conditional Access, SSO |
| **Intune** | MDM enrolled | Compliance, baselines, apps, BitLocker, LAPS, update rings, scripts |

Every policy assigned to the user's security group starts applying automatically. No further device touch needed.

---

## Troubleshooting Quick Reference

| Symptom | Cause | Fix |
|:--------|:------|:----|
| `AzureAdPrt: NO` | Signed in with local account | Sign out, sign in with work email |
| `WorkplaceJoined: YES` only | Registered, not joined | Disconnect, reboot, re-join properly |
| MDM enrollment empty | Auto-enrollment didn't fire | `Start-Process "ms-device-enrollment:?mode=mdm"` |
| MDM dialog can't find endpoint | Auto-discover failed | Enter URL manually: `https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc` |
| Device shows Personal | Default for non-Autopilot | Change to Corporate in portal |
| Policies not applying | Hasn't synced yet | Force sync via scheduled task or wait 1-2 hours |
