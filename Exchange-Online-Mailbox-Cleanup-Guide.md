# Exchange Online Mailbox Cleanup & Legacy Alias Management

> **A complete guide to fixing GUID-named mailboxes and adding legacy domain aliases in Microsoft 365 / Exchange Online**

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Part 1: Environment Setup](#part-1-environment-setup)
  - [PowerShell Execution Policy](#powershell-execution-policy)
  - [Installing Exchange Online Module](#installing-exchange-online-module)
  - [Connecting to Exchange Online](#connecting-to-exchange-online)
- [Part 2: Diagnosing the Problem](#part-2-diagnosing-the-problem)
  - [Identifying GUID-Named Mailboxes](#identifying-guid-named-mailboxes)
  - [Understanding Mailbox Properties](#understanding-mailbox-properties)
- [Part 3: Fixing GUID Mailbox Names](#part-3-fixing-guid-mailbox-names)
  - [Script 1: Fix-GuidMailboxNames.ps1](#script-1-fix-guidmailboxnamesps1)
  - [Script 2: Fix-GuidMailboxNames-Part2.ps1](#script-2-fix-guidmailboxnames-part2ps1)
- [Part 4: Adding Legacy Domain Aliases](#part-4-adding-legacy-domain-aliases)
  - [Script: Add-LegacyAliases.ps1](#script-add-legacyaliasesps1)
- [Part 5: Verification](#part-5-verification)
- [Troubleshooting](#troubleshooting)
- [Quick Reference](#quick-reference)

---

## Overview

This guide addresses two common Exchange Online issues often caused by improper mailbox provisioning:

| Problem                    | Symptom                                                                       | Solution                     |
|:-------------------------- |:----------------------------------------------------------------------------- |:---------------------------- |
| **GUID Mailbox Names**     | `Name` field shows `a7f35690-65ca-45e3-9247-e59eb52ab242` instead of `jsmith` | Fix-GuidMailboxNames scripts |
| **Missing Legacy Aliases** | Users can't receive email at old domain addresses                             | Add-LegacyAliases script     |

### When This Happens

- Mailboxes auto-created before user objects were properly configured
- Migration artifacts from hybrid environments
- MSP misconfigurations during tenant setup
- Azure AD / Entra ID sync issues

---

## Prerequisites

### Required Access

- [x] Global Administrator or Exchange Administrator role
- [x] PowerShell 5.1+ or PowerShell Core 7+
- [x] Internet connectivity to Microsoft 365

### Required Files

| File                             | Purpose                                   |
|:-------------------------------- |:----------------------------------------- |
| `exo_bootstrap.ps1`              | Environment setup and module installation |
| `Fix-GuidMailboxNames.ps1`       | Fixes the Alias property                  |
| `Fix-GuidMailboxNames-Part2.ps1` | Fixes the Name property                   |
| `Add-LegacyAliases.ps1`          | Adds legacy domain email aliases          |

---

## Part 1: Environment Setup

### PowerShell Execution Policy

> ⚠️ **Windows blocks unsigned scripts by default.** You must configure the execution policy before running any scripts.

#### Option A: Set Policy Permanently (Recommended)

```powershell
# Allow locally-created scripts to run
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Trust PSGallery for module installation
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
```

#### Option B: Bypass for Current Session Only

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Unblocking Downloaded Scripts

> ⚠️ **Critical Step!** Files downloaded from the internet are marked as "blocked" by Windows and will not execute even with proper execution policy.

#### Unblock Individual Files

```powershell
Unblock-File .\Fix-GuidMailboxNames.ps1
Unblock-File .\Fix-GuidMailboxNames-Part2.ps1
Unblock-File .\Add-LegacyAliases.ps1
```

#### Unblock All Scripts in a Folder

```powershell
Get-ChildItem -Path . -Filter *.ps1 | Unblock-File
```

#### Verify a File is Unblocked

```powershell
Get-Item .\Fix-GuidMailboxNames.ps1 -Stream * | Where-Object Stream -eq 'Zone.Identifier'
```

*If no output, the file is unblocked.*

---

### Installing Exchange Online Module

#### Quick Install

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
```

#### Full Bootstrap (Recommended for New Machines)

Use the bootstrap script for a complete environment setup:

```powershell
# Standard setup with PSGallery trust and execution policy
.\exo_bootstrap.ps1 -TrustPSGallery -SetExecutionPolicy

# If you have module corruption issues
.\exo_bootstrap.ps1 -NukeExisting -TrustPSGallery

# Just run diagnostics (no changes)
.\exo_bootstrap.ps1 -DiagnosticsOnly
```

**Bootstrap Script Features:**

- ✅ Enforces TLS 1.2 (required for PSGallery)
- ✅ Installs/updates NuGet package provider
- ✅ Updates PowerShellGet module
- ✅ Trusts PSGallery repository
- ✅ Sets ExecutionPolicy
- ✅ Installs ExchangeOnlineManagement
- ✅ Unblocks module files
- ✅ Validates installation

---

### Connecting to Exchange Online

#### Interactive Login (Browser Popup)

```powershell
Connect-ExchangeOnline -ShowBanner:$false
```

#### Specify Account

```powershell
Connect-ExchangeOnline -UserPrincipalName admin@yourdomain.com -ShowBanner:$false
```

#### Verify Connection

```powershell
Get-OrganizationConfig | Select-Object DisplayName, Name
```

#### Disconnect When Done

```powershell
Disconnect-ExchangeOnline -Confirm:$false
```

---

## Part 2: Diagnosing the Problem

### Identifying GUID-Named Mailboxes

#### List All Mailboxes with Key Properties

```powershell
Get-Mailbox -ResultSize Unlimited | 
    Select-Object Name, Alias, DisplayName, UserPrincipalName, PrimarySmtpAddress | 
    Format-Table -AutoSize
```

**Example Output (Problem State):**

```
Name                                     Alias    DisplayName      UserPrincipalName
----                                     -----    -----------      -----------------
a7f35690-65ca-45e3-9247-e59eb52ab242    a7f35... Alexander Tran   atran@domain.com
JSmith                                   JSmith   John Smith       jsmith@domain.com
53dae3e3-c949-44cf-a6a9-4a53739db7c7    53dae... Amanda Williams  awilliams@domain.com
```

*Notice: Some have proper names (`JSmith`), others have GUIDs.*

#### Count Affected Mailboxes

```powershell
$guid = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
(Get-Mailbox -ResultSize Unlimited | Where-Object { $_.Name -match $guid }).Count
```

---

### Understanding Mailbox Properties

> ⚠️ **Important:** `Name` and `Alias` are **different properties** in Exchange.

| Property               | Description                                    | Example                  |
|:---------------------- |:---------------------------------------------- |:------------------------ |
| **Name**               | Mailbox object name (appears in admin console) | `jsmith`                 |
| **Alias**              | Mail nickname (used for email generation)      | `jsmith`                 |
| **DisplayName**        | Full name shown in address book                | `John Smith`             |
| **UserPrincipalName**  | Sign-in address                                | `jsmith@domain.com`      |
| **PrimarySmtpAddress** | Primary email address                          | `jsmith@domain.com`      |
| **EmailAddresses**     | All email aliases (SMTP addresses)             | `smtp:jsmith@legacy.com` |

#### View All Properties for a Specific User

```powershell
Get-Mailbox -Identity jsmith@domain.com | 
    Select-Object Name, Alias, DisplayName, UserPrincipalName, PrimarySmtpAddress
```

#### View Email Aliases

```powershell
Get-Mailbox -Identity jsmith@domain.com | 
    Select-Object -ExpandProperty EmailAddresses
```

---

## Part 3: Fixing GUID Mailbox Names

> **Order matters!** Run these scripts in sequence.

### Script 1: Fix-GuidMailboxNames.ps1

*Fixes the **Alias** property on mailboxes with GUID names.*

#### Preview Changes (No Modifications)

```powershell
.\Fix-GuidMailboxNames.ps1 -WhatIf
```

**Expected Output:**

```
Found 54 mailboxes with GUID names.

What if: Performing the operation "Change Alias from 
'a7f35690-65ca-45e3-9247-e59eb52ab242' to 'atran'" on target 
"John Smight (jsmith@domain.com)".
```

#### Execute Changes

```powershell
.\Fix-GuidMailboxNames.ps1
```

**Expected Output:**

```
[SUCCESS] John Smith : a7f35690-65ca-45e3-9247-e59eb52ab242 -> jsmith
[SUCCESS] Jane Doe : 53dae3e3-c949-44cf-a6a9-4a53739db7c7 -> jdoe
...

===== SUMMARY =====
Total GUID mailboxes found: 54
Successfully fixed: 54
Errors: 0
```

---

### Script 2: Fix-GuidMailboxNames-Part2.ps1

*Fixes the **Name** property on mailboxes with GUID names.*

> ⚠️ Run this **after** Script 1 completes successfully.

#### Preview Changes

```powershell
.\Fix-GuidMailboxNames-Part2.ps1 -WhatIf
```

#### Execute Changes

```powershell
.\Fix-GuidMailboxNames-Part2.ps1
```

---

## Part 4: Adding Legacy Domain Aliases

### Script: Add-LegacyAliases.ps1

*Adds legacy domain email aliases to mailboxes so users can receive email at old addresses.*

#### Configuration

Before running, edit the script to specify your legacy domains:

```powershell
# Line 30 in Add-LegacyAliases.ps1
$LegacyDomains = @("legacydomain1.org", "legacydomain2.org")
```

#### Usage Options

##### Option 1: Process All Mailboxes

```powershell
# Preview
.\Add-LegacyAliases.ps1 -WhatIf

# Execute
.\Add-LegacyAliases.ps1
```

##### Option 2: Process Specific Users (CSV)

Create a CSV file with one column:

```csv
UserPrincipalName
jsmith@domain.com
jdoe@domain.com
```

Run with CSV:

```powershell
# Preview
.\Add-LegacyAliases.ps1 -CsvPath .\users.csv -WhatIf

# Execute
.\Add-LegacyAliases.ps1 -CsvPath .\users.csv
```

#### CSV Column Names

The script accepts any of these column names:

- `UserPrincipalName`
- `UPN`
- `Email`

---

## Part 5: Verification

### Verify Name and Alias Fixed

```powershell
Get-Mailbox -Identity jsmith@domain.com | 
    Select-Object Name, Alias, DisplayName
```

**Expected:**

```
Name   : jsmith
Alias  : jsmith
DisplayName : John Smith
```

### Verify Email Aliases Added

```powershell
Get-Mailbox -Identity jsmith@domain.com | 
    Select-Object -ExpandProperty EmailAddresses
```

**Expected:**

```
SMTP:jsmith@domain.com
smtp:jsmith@legacydomain1.org
smtp:jsmith@legacydomain2.org
```

*Note: Uppercase `SMTP:` indicates primary address. Lowercase `smtp:` indicates aliases.*

### Bulk Verification

```powershell
# Check for any remaining GUID names
$guid = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
Get-Mailbox -ResultSize Unlimited | 
    Where-Object { $_.Name -match $guid } | 
    Select-Object Name, DisplayName
```

*Should return empty if all fixed.*

---

## Troubleshooting

### Error: "File cannot be loaded... not digitally signed"

**Cause:** PowerShell execution policy is blocking the script.

**Fix:**

```powershell
Unblock-File .\YourScript.ps1
# or
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

### Error: "A positional parameter cannot be found that accepts argument '--WhatIf'"

**Cause:** Using Linux-style double dash instead of PowerShell single dash.

**Fix:** Use single dash:

```powershell
# Wrong
.\Script.ps1 --WhatIf

# Correct
.\Script.ps1 -WhatIf
```

---

### Changes Not Appearing Immediately

**Cause:** Exchange Online caches mailbox data. Changes may take 5-15 minutes to propagate.

**Fix:** Wait, or refresh by re-running `Get-Mailbox`:

```powershell
# Force refresh
$mb = Get-Mailbox -Identity user@domain.com
$mb | Select-Object Name, Alias
```

---

### Error: "The term 'Connect-ExchangeOnline' is not recognized"

**Cause:** Exchange Online module not installed or not loaded.

**Fix:**

```powershell
# Install
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force

# Import
Import-Module ExchangeOnlineManagement
```

---

### Script Hangs with No Output

**Cause:** Processing all mailboxes in a large organization takes time.

**Fix:** Use `-CsvPath` to process a smaller subset, or wait for completion.

---

## Quick Reference

### One-Time Setup

```powershell
# 1. Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 2. Trust PSGallery
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# 3. Install module
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
```

### Per-Session Workflow

```powershell
# 1. Unblock scripts (first time only)
Get-ChildItem *.ps1 | Unblock-File

# 2. Connect
Connect-ExchangeOnline -ShowBanner:$false

# 3. Run scripts
.\Fix-GuidMailboxNames.ps1
.\Fix-GuidMailboxNames-Part2.ps1
.\Add-LegacyAliases.ps1

# 4. Disconnect
Disconnect-ExchangeOnline -Confirm:$false
```

### Key Commands

| Task                  | Command                                                                                 |
|:--------------------- |:--------------------------------------------------------------------------------------- |
| List all mailboxes    | `Get-Mailbox -ResultSize Unlimited`                                                     |
| View specific mailbox | `Get-Mailbox -Identity user@domain.com`                                                 |
| View email aliases    | `Get-Mailbox -Identity user@domain.com \| Select-Object -ExpandProperty EmailAddresses` |
| Count GUID mailboxes  | `(Get-Mailbox \| Where-Object { $_.Name -match '^[0-9a-f]{8}-' }).Count`                |
| Unblock all scripts   | `Get-ChildItem *.ps1 \| Unblock-File`                                                   |

---

## Appendix: Complete Script Execution Order

```
┌─────────────────────────────────────────────────────────────────┐
│  STEP 1: Environment Setup                                      │
├─────────────────────────────────────────────────────────────────┤
│  • Set-ExecutionPolicy                                          │
│  • Install-Module ExchangeOnlineManagement                      │
│  • Unblock-File (all .ps1 files)                               │
│  • Connect-ExchangeOnline                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  STEP 2: Diagnose                                               │
├─────────────────────────────────────────────────────────────────┤
│  • Get-Mailbox -ResultSize Unlimited | Select Name, Alias...   │
│  • Identify mailboxes with GUID names                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  STEP 3: Fix GUID Names (Alias)                                 │
├─────────────────────────────────────────────────────────────────┤
│  • .\Fix-GuidMailboxNames.ps1 -WhatIf     (preview)            │
│  • .\Fix-GuidMailboxNames.ps1             (execute)            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  STEP 4: Fix GUID Names (Name)                                  │
├─────────────────────────────────────────────────────────────────┤
│  • .\Fix-GuidMailboxNames-Part2.ps1 -WhatIf    (preview)       │
│  • .\Fix-GuidMailboxNames-Part2.ps1            (execute)       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  STEP 5: Add Legacy Aliases                                     │
├─────────────────────────────────────────────────────────────────┤
│  • .\Add-LegacyAliases.ps1 -WhatIf            (preview)        │
│  • .\Add-LegacyAliases.ps1                    (execute)        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  STEP 6: Verify & Disconnect                                    │
├─────────────────────────────────────────────────────────────────┤
│  • Get-Mailbox | Select Name, Alias... (verify changes)        │
│  • Disconnect-ExchangeOnline -Confirm:$false                   │
└─────────────────────────────────────────────────────────────────┘
```

---

*Last updated: February 2026*
