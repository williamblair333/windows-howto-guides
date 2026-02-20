# 🖥️ Intune Onboarding & Lifecycle Management Guide

```
╔═══════════════════════════════════════════════════════════════════╗
║  Microsoft Intune — Production Deployment Blueprint              ║
║  Example Organization: Contoso Ltd.                              ║
║  Target: 50–200 Windows Endpoints | Mixed E3 + F3 Licensing      ║
╚═══════════════════════════════════════════════════════════════════╝
```

---

## 📋 Table of Contents

| #  | Section                                                    | Phase        |
|:--:|:-----------------------------------------------------------|:-------------|
| 1  | [Executive Overview](#-1-executive-overview)               | —            |
| 2  | [Architecture Overview](#-2-architecture-overview)         | —            |
| 3  | [License Capabilities Matrix](#-3-license-capabilities-matrix) | —        |
| 4  | [Foundation Configuration](#-4-phase-1--foundation-configuration) | Phase 1 |
| 5  | [Device Enrollment Strategy](#-5-phase-2--device-enrollment-strategy) | Phase 2 |
| 6  | [Windows 11 Readiness](#-6-phase-3--windows-11-readiness-assessment) | Phase 3 |
| 7  | [Compliance Strategy](#-7-phase-4--compliance-strategy-audit--enforce) | Phase 4 |
| 8  | [BitLocker & Key Escrow](#-8-phase-5--bitlocker--recovery-key-management) | Phase 5 |
| 9  | [Security Baselines](#-9-phase-6--security-baseline-configuration) | Phase 6 |
| 10 | [Update Management](#-10-phase-7--windows-update-management) | Phase 7    |
| 11 | [Conditional Access](#-11-phase-8--conditional-access-integration) | Phase 8 |
| 12 | [Application Lifecycle](#-12-phase-9--application-lifecycle-management) | Phase 9 |
| 13 | [Device Lifecycle](#-13-phase-10--device-lifecycle-model)  | Phase 10     |
| 14 | [Governance Model](#-14-operational-governance-model)      | Ongoing      |
| 15 | [Deployment Timeline](#-15-recommended-deployment-order)   | —            |
| 16 | [Common Pitfalls](#-16-common-pitfalls)                    | —            |
| 17 | [Reference Checklist](#-17-reference-checklist)            | —            |

---

## 📝 1. Executive Overview

This document provides a **production-ready onboarding blueprint** for deploying Microsoft Intune across a mixed-license environment (E3 + F3) with approximately 50–200 Windows endpoints across multiple physical sites.

### Objectives

- ✅ Enable controlled Windows device enrollment across all license tiers
- ✅ Determine Windows 11 hardware readiness using Intune-native reporting
- ✅ Implement scalable security posture with phased compliance enforcement
- ✅ Ensure BitLocker recovery keys are escrowed **before** enforcement
- ✅ Establish full device lifecycle governance
- ✅ Maximize existing M365 license capabilities before adding cost

### Core Philosophy

```
┌─────────┐    ┌───────────┐    ┌──────────┐    ┌──────────┐    ┌────────┐
│  AUDIT  │ ─→ │ STABILIZE │ ─→ │ ENFORCE  │ ─→ │ AUTOMATE │ ─→ │ EXPAND │
└─────────┘    └───────────┘    └──────────┘    └──────────┘    └────────┘
```

---

## 🏗️ 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     IDENTITY LAYER                              │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────┐ │
│  │  Entra ID    │  │  Entra Join   │  │  Hybrid Join (opt.)  │ │
│  └──────────────┘  └───────────────┘  └──────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                    MANAGEMENT LAYER                             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          Microsoft Intune (MDM Authority)                │  │
│  │          License included with E3 and F3                 │  │
│  └──────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    ENFORCEMENT LAYER                            │
│  ┌────────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐  │
│  │ Compliance │ │ Config   │ │ Security │ │  Conditional   │  │
│  │ Policies   │ │ Profiles │ │ Baselines│ │  Access        │  │
│  └────────────┘ └──────────┘ └──────────┘ └────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

> ⚠️ **Key Constraint:** E3 and F3 licenses both include Intune enrollment, but F3 has reduced capabilities. See [Section 3](#-3-license-capabilities-matrix) for the full comparison. **All policies must be tested against both license tiers** before broad deployment.

---

## 🔑 3. License Capabilities Matrix

Understanding license boundaries prevents deployment failures. F3 users will enroll successfully but hit feature limits in specific areas.

| Capability                        | E3  | F3  | Notes                                      |
|:----------------------------------|:---:|:---:|:-------------------------------------------|
| Intune MDM Enrollment             | ✅  | ✅  | Both support Entra Join + auto-enroll       |
| Compliance Policies               | ✅  | ✅  | Full support both tiers                     |
| Configuration Profiles            | ✅  | ✅  | Full support both tiers                     |
| Security Baselines                | ✅  | ✅  | Full support both tiers                     |
| Conditional Access                | ✅  | ✅  | Requires Entra ID P1 (included in both)     |
| Windows Update Rings              | ✅  | ✅  | Full support both tiers                     |
| BitLocker Management              | ✅  | ✅  | Key escrow to Entra works for both          |
| Microsoft 365 Apps Deployment     | ✅  | ❌  | F3 = web/mobile apps only                   |
| Win32 App Deployment              | ✅  | ✅  | Full support both tiers                     |
| Windows Autopilot                 | ✅  | ✅  | Both support device provisioning            |
| Autopilot Device Preparation      | ✅  | ❌  | E3 only — newer streamlined flow            |
| Endpoint Analytics                | ✅  | ⚠️  | F3 has reduced reporting                    |
| Remote Actions (Wipe/Retire)      | ✅  | ✅  | Full support both tiers                     |

> 🛑 **Critical Actions:**
> - Tag E3 and F3 users into **separate security groups** for targeted app deployment
> - **Do NOT** assign Microsoft 365 Apps (desktop) to F3 users — deployment will fail
> - Use Win32 app packaging for any LOB apps needed on F3 devices
> - Test all policies against at least one F3-licensed device during pilot

---

## ⚙️ 4. Phase 1 — Foundation Configuration

### 4.1 Confirm Tenant Readiness

Verify in the **Microsoft Intune admin center** (`intune.microsoft.com`):

1. Navigate: **Devices → Enrollment → Windows**
2. Confirm `MDM user scope` = **All** (or target group)
3. Confirm `MAM user scope` = **None** (unless mobile app management needed)
4. Verify default MDM URLs are present:

| URL Type      | Expected Value                                                          |
|:--------------|:------------------------------------------------------------------------|
| Discovery     | `https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc`|
| Terms of Use  | `https://portal.manage.microsoft.com/TermsofUse.aspx`                  |
| Compliance    | `https://portal.manage.microsoft.com/?portalAction=Compliance`         |

### 4.2 Confirm Clean Starting State

Before deploying anything, verify:

- [ ] No existing compliance policies (**Devices → Compliance**)
- [ ] No existing Conditional Access rules blocking enrollment (**Entra ID → Security → Conditional Access**)
- [ ] No conflicting MDM authorities (check for hybrid config conflicts)
- [ ] No legacy enrollment restrictions blocking devices unintentionally

### 4.3 Create Foundation Security Groups

Create in **Entra ID → Groups**:

| Group Name               | Type     | Membership | Purpose                            |
|:-------------------------|:---------|:-----------|:-----------------------------------|
| `SG-INTUNE-PILOT`        | Security | Assigned   | Initial 5–10 test users            |
| `SG-INTUNE-E3-USERS`     | Security | Assigned   | All E3-licensed staff              |
| `SG-INTUNE-F3-USERS`     | Security | Assigned   | All F3-licensed frontline staff     |
| `SG-INTUNE-ALL-USERS`    | Security | Assigned   | All Intune-managed users           |
| `SG-INTUNE-BREAKGLASS`   | Security | Assigned   | Emergency admin account(s)         |

> 🔒 The **break-glass account must be excluded from ALL Conditional Access policies.**

---

## 📲 5. Phase 2 — Device Enrollment Strategy

### 5.1 Default Enrollment Model

**Entra Join + Automatic MDM Enrollment** *(recommended for all new/reimaged devices)*

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  User     │    │  Device   │    │   MDM    │    │  Device   │    │ Policies │
│  signs in │ ─→ │  joins    │ ─→ │  auto-   │ ─→ │  appears  │ ─→ │  begin   │
│  with M365│    │  Entra ID │    │  enrolls │    │  in Intune│    │ applying │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
```

This works **identically** for E3 and F3 users.

### 5.2 Controlled Pilot Enrollment

Before broad rollout, enroll **5–10 devices** representing your actual environment:

**Pilot group should include:**

- 🖥️ At least **2 E3-licensed users** (admin/office roles)
- 🖥️ At least **2 F3-licensed users** (frontline/field roles)
- 🖥️ Mix of hardware ages (newest and oldest machines)
- 🖥️ At least 1 device from **each physical site** if possible

Assign `SG-INTUNE-PILOT` to compliance policies (audit), security baselines, and update rings. **Monitor for 2–3 weeks** before expanding.

### 5.3 Bulk Enrollment Options for Existing Devices

| Option | Method                          | Complexity | Best For                        |
|:------:|:--------------------------------|:----------:|:--------------------------------|
| **A**  | User-driven (Settings → Connect)| Low        | Small fleets, minimal IT touch  |
| **B**  | Provisioning package (USB)      | Medium     | No user interaction needed      |
| **C**  | Windows Autopilot               | Medium     | New/reimaged devices            |
| **D**  | GPO-triggered enrollment        | High       | Hybrid join only (on-prem AD)   |

#### Option A — User-Driven Enrollment *(simplest)*

```
Settings → Accounts → Access work or school → Connect → Enter M365 email
```

#### Option B — Provisioning Package

1. Create package in **Windows Configuration Designer**
2. Export to USB
3. Apply: `Settings → Accounts → Access work or school → Add provisioning package`

#### Option C — Windows Autopilot

See [Phase 10](#-13-phase-10--device-lifecycle-model) for full setup.

> 💡 **Recommendation:** For an environment under 200 devices with a single IT administrator, **Option A** with clear written instructions is the most practical starting point. Move to Autopilot for all future device refreshes.

---

## 📊 6. Phase 3 — Windows 11 Readiness Assessment

### 6.1 Windows 11 Hardware Requirements

| Component     | Minimum Requirement                                |
|:--------------|:---------------------------------------------------|
| **CPU**       | 1 GHz, 2+ cores, 64-bit (must be on MS approved list) |
| **RAM**       | 4 GB *(8 GB recommended)*                         |
| **Storage**   | 64 GB                                              |
| **TPM**       | Version 2.0                                        |
| **Secure Boot** | Capable and enabled                             |
| **Display**   | 9" diagonal, 720p                                  |

### 6.2 Use the Built-In Readiness Report

> 🛑 **Do NOT rely on dynamic group queries** for hardware eligibility. OS version filters alone cannot validate TPM, Secure Boot, or CPU compatibility.

Use **Intune's native report** instead:

1. Navigate: **Reports → Endpoint Analytics → Work from Anywhere**
2. Select the **Windows 11 readiness** tab
3. Review per-device status:

| Status          | Meaning                                  |
|:----------------|:-----------------------------------------|
| ✅ Capable      | Meets all hardware requirements          |
| ❌ Not Capable  | Fails one or more checks                 |
| ⚠️ Unknown      | Insufficient data — device needs check-in|

4. **Export the report** for planning and budgeting

### 6.3 Create Device Groups Based on Results

| Group Name          | Type     | Purpose                               |
|:--------------------|:---------|:--------------------------------------|
| `DG-Win11-Ready`    | Security | Devices confirmed capable             |
| `DG-Win11-Not-Ready`| Security | Devices needing replacement/upgrade   |

### 6.4 Dynamic Group for All Enrolled Windows Devices

This general-purpose group captures all managed Windows devices for policy targeting:

```
(device.deviceOSType -eq "Windows") and (device.managementType -eq "MDM")
```

---

## 🛡️ 7. Phase 4 — Compliance Strategy (Audit → Enforce)

Compliance policies define the **minimum security posture** a device must meet. Deploy in **audit mode first**, then enforce after validation.

### 7.1 🔍 Audit Mode — Deploy First

> Navigate: **Devices → Compliance → Create policy → Windows 10 and later**

**Policy name:** `CP-Windows-Compliance-Audit`

| Setting                    | Value                          |
|:---------------------------|:-------------------------------|
| Require BitLocker          | ⏸️ Not configured *(see Phase 5 first)* |
| Require Secure Boot        | ✅ Require                     |
| Require TPM                | ✅ Require *(report only)*     |
| Minimum OS version         | `10.0.19045` *(Win10 22H2)*   |
| Require code integrity     | ✅ Require                     |
| Firewall                   | ✅ Require                     |
| Antivirus                  | ✅ Require                     |
| Antispyware                | ✅ Require                     |
| Real-time protection       | ✅ Require                     |

**Actions for noncompliance:**

| Action                       | Timing              |
|:-----------------------------|:---------------------|
| Mark device noncompliant     | After **7 days** (grace period) |
| Send email notification      | Optional             |

**Assign to:** `SG-INTUNE-PILOT`

> ⚠️ **Do NOT enable Conditional Access yet.** Observe the compliance dashboard for 2–3 weeks. Identify which devices fail and why.

### 7.2 🔒 Enforced Mode — Deploy After Stabilization

After audit confirms acceptable compliance rates, create:

**Policy name:** `CP-Windows-Compliance-Enforced`

**Changes from audit:**

| Setting                    | Change                          |
|:---------------------------|:--------------------------------|
| Require BitLocker          | ✅ Require *(only after Phase 5 confirms escrow)* |
| Require Secure Boot        | ✅ Require                      |
| Require TPM                | ✅ Require                      |
| Noncompliance grace period | **1 day** (or immediate)        |

**Assign to:** `SG-INTUNE-ALL-USERS` *(exclude break-glass)*

Integrate with **Conditional Access** ([Phase 8](#-11-phase-8--conditional-access-integration)) to block noncompliant devices from M365 resources.

---

## 🔐 8. Phase 5 — BitLocker & Recovery Key Management

```
╔═══════════════════════════════════════════════════════════════════╗
║  ⛔ CRITICAL                                                     ║
║  Do NOT require BitLocker in compliance policy until recovery    ║
║  key escrow to Entra ID is CONFIRMED WORKING.                   ║
║                                                                  ║
║  Requiring encryption without key backup risks PERMANENT         ║
║  DATA LOSS if a user forgets their PIN or a device fails.        ║
╚═══════════════════════════════════════════════════════════════════╝
```

### 8.1 Configure BitLocker Policy

> Navigate: **Endpoint Security → Disk encryption → Create policy**

**Platform:** Windows 10 and later  
**Profile:** BitLocker

| Setting                                     | Value                        |
|:--------------------------------------------|:-----------------------------|
| Require device encryption                   | Yes                          |
| Allow standard users to enable during Autopilot | Yes                      |
| Encryption method                           | XTS-AES 128-bit *(or 256)*   |
| Recovery key rotation                       | Enabled                      |
| **Save recovery info to Entra ID**          | **Yes (REQUIRED)**           |
| Configure recovery key escrow               | Before enabling encryption   |

**Assign to:** `SG-INTUNE-PILOT` first.

### 8.2 ✅ Verify Key Escrow Is Working

Before expanding BitLocker enforcement:

1. Navigate: **Devices → All devices → [Select pilot device] → Recovery keys**
2. Confirm at least one recovery key is stored
3. Test: Note the key ID, confirm it matches what the device reports

> ✅ **Only after confirming escrow works on pilot devices** should you enable BitLocker requirement in compliance policy and expand to all users.

### 8.3 Manual Key Backup (Existing Encrypted Devices)

If devices are already encrypted but keys are **not** in Entra, run on each device (elevated PowerShell):

```powershell
$BLV = Get-BitLockerVolume -MountPoint "C:"
BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $BLV.KeyProtector[1].KeyProtectorId
```

Verify: **Entra ID → Devices → [Select device] → BitLocker keys**

---

## 🏰 9. Phase 6 — Security Baseline Configuration

Security baselines apply **Microsoft's recommended hardening settings** as a single configuration profile covering Defender, firewall, credential protection, and attack surface reduction.

### 9.1 Deploy Baseline

> Navigate: **Endpoint Security → Security Baselines → Security Baseline for Windows**

**Profile name:** `CFG-Windows-SecurityBaseline`

| Setting                         | Recommended Value               |
|:--------------------------------|:--------------------------------|
| Microsoft Defender Antivirus    | ✅ Enabled                      |
| Cloud-delivered protection      | ✅ Enabled                      |
| Windows Firewall (all profiles) | ✅ Enabled                      |
| Credential Guard                | ✅ Enabled *(if hardware supports)* |
| Attack Surface Reduction rules  | ⚠️ **Audit mode first**, then Block |
| Network protection              | ✅ Enabled                      |
| SmartScreen                     | ✅ Enabled                      |

**Assign to:** `SG-INTUNE-PILOT`

**Monitor for 2 weeks.** Watch for:

- 🔴 Application compatibility issues (ASR rules can block legitimate apps)
- 🔴 User complaints about blocked actions
- 🔴 Defender false positives

After stabilization → assign to `SG-INTUNE-ALL-USERS`.

### 9.2 Conflict Resolution

> 💡 If a security baseline setting conflicts with a separate configuration profile, the **most restrictive setting wins** — but the device may report a conflict error.
>
> **Best practice:** Use security baselines as the **primary** hardening mechanism. Only create separate configuration profiles for settings *not* covered by the baseline.

---

## 🔄 10. Phase 7 — Windows Update Management

Update rings control when quality (security) and feature (version) updates install.

### 10.1 IT Testing Ring

**Profile name:** `UR-IT-Testing`

| Setting                  | Value                            |
|:-------------------------|:---------------------------------|
| Quality update deferral  | **0 days**                       |
| Feature update deferral  | **0 days**                       |
| Automatic install        | During maintenance window        |
| Restart grace period     | 2 days                           |

**Assign to:** `SG-INTUNE-PILOT` *(or dedicated IT devices group)*

> 💡 **Purpose:** IT sees updates first, catches issues before production.

### 10.2 Production Ring

**Profile name:** `UR-Standard-Production`

| Setting                  | Value                            |
|:-------------------------|:---------------------------------|
| Quality update deferral  | **7 days**                       |
| Feature update deferral  | **30 days**                      |
| Automatic install        | Outside active hours (6 PM–6 AM) |
| Restart grace period     | 3 days                           |
| Deadline                 | 5 days after install *(forces restart)* |

**Assign to:** `SG-INTUNE-ALL-USERS` *(after pilot validation)*

### 10.3 Feature Update Targeting *(Optional)*

To control which Windows version devices receive:

> Navigate: **Devices → Windows → Feature updates**

Create profile targeting a specific version (e.g., Windows 11 24H2) and assign **only** to `DG-Win11-Ready`. This prevents ineligible devices from attempting a failed upgrade.

---

## 🚪 11. Phase 8 — Conditional Access Integration

Conditional Access **blocks noncompliant devices** from accessing M365 resources (email, SharePoint, Teams). Only enable after compliance policies are stable.

### 11.1 Prerequisites

> ⚠️ **Before enabling, confirm:**
> - Compliance policies deployed and stable for **3+ weeks**
> - **90%+** of enrolled devices showing compliant
> - Break-glass account identified and excluded
> - Users **notified** of upcoming enforcement

### 11.2 Create Policy

> Navigate: **Entra ID → Security → Conditional Access → Create new policy**

**Policy name:** `CA-Require-Compliant-Device`

| Setting         | Value                                              |
|:----------------|:---------------------------------------------------|
| Users           | All users                                          |
| Exclude         | `SG-INTUNE-BREAKGLASS`                             |
| Cloud apps      | All *(or start with Exchange + SharePoint)*        |
| Conditions      | Any device platform                                |
| Grant           | **Require device to be marked as compliant**       |
| Enable policy   | 🟡 **Report-only FIRST**                           |

### 11.3 Validation Workflow

```
┌─────────────────────┐    ┌─────────────────────┐    ┌──────────────────┐
│  1. Report-only     │    │  2. Review sign-in   │    │  3. Remediate    │
│     mode for        │ ─→ │     logs for         │ ─→ │     failures     │
│     1–2 weeks       │    │     "would block"    │    │     before On    │
└─────────────────────┘    └─────────────────────┘    └──────────────────┘
```

1. Navigate: **Entra ID → Sign-in logs**
2. Filter: **Conditional Access → Report-only: Failure**
3. Identify which users/devices would be blocked
4. Remediate → then switch policy to **On**

---

## 📦 12. Phase 9 — Application Lifecycle Management

### 12.1 Standard Application Deployment

| Application              | Type          | Target Group            | Notes                       |
|:-------------------------|:--------------|:------------------------|:----------------------------|
| Microsoft 365 Apps       | M365 Suite    | `SG-INTUNE-E3-USERS`   | ⛔ E3 only — never target F3|
| Corporate VPN client     | Win32         | `SG-INTUNE-ALL-USERS`  | Package as `.intunewin`     |
| Approved browser         | Win32 / Store | `SG-INTUNE-ALL-USERS`  | Edge is pre-installed       |
| Endpoint security agent  | Win32         | `SG-INTUNE-ALL-USERS`  | e.g., CrowdStrike Falcon    |
| LOB applications         | Win32         | Relevant groups         | Per-department targeting     |

### 12.2 Win32 App Packaging Workflow

```
┌────────────┐    ┌─────────────────┐    ┌──────────────┐    ┌──────────────┐
│  Source     │    │  Win32 Content  │    │  Upload to   │    │  Assign:     │
│  .exe/.msi │ ─→ │  Prep Tool      │ ─→ │  Intune      │ ─→ │  Required or │
│            │    │  → .intunewin   │    │              │    │  Available   │
└────────────┘    └─────────────────┘    └──────────────┘    └──────────────┘
```

**Package command:**
```bash
IntuneWinAppUtil.exe -c <source_folder> -s <setup.exe> -o <output_folder>
```

**Configure in Intune** (`Apps → Windows → Add → Windows app (Win32)`):

| Setting           | Example Value                                   |
|:------------------|:------------------------------------------------|
| Install command   | `setup.exe /silent`                             |
| Uninstall command | `setup.exe /uninstall /silent`                  |
| Detection rule    | File exists, registry key, or MSI product code  |
| Requirements      | OS version, disk space, RAM                     |
| Assignment        | **Required** (auto) or **Available** (Company Portal) |

### 12.3 Update Strategy

| App Type       | Update Method                                        |
|:---------------|:-----------------------------------------------------|
| M365 Apps      | Update channel (Monthly Enterprise recommended)      |
| Win32 apps     | New version in Intune → supersede old version        |
| Store apps     | Auto-update via Microsoft Store                      |

---

## ♻️ 13. Phase 10 — Device Lifecycle Model

### 13.1 🆕 Provisioning — Windows Autopilot

Autopilot automates device setup so new devices arrive **ready to use** without manual imaging.

#### Step 1: Register Hardware IDs

**Option A** — Vendor provides CSV at purchase  
**Option B** — Extract from existing device:

```powershell
Install-Script -Name Get-WindowsAutopilotInfo
Get-WindowsAutopilotInfo -OutputFile C:\autopilot.csv
```

Upload CSV: **Devices → Windows → Enrollment → Device import**

#### Step 2: Create Deployment Profile

> Navigate: **Devices → Windows → Enrollment → Deployment profiles**

**Profile name:** `AP-Standard-UserDriven`

| Setting                       | Value                      |
|:------------------------------|:---------------------------|
| Deployment mode               | User-driven                |
| Join type                     | Entra joined               |
| Skip privacy settings         | Yes                        |
| Skip EULA                     | Yes                        |
| Hide change account options   | Yes                        |
| Account type                  | **Standard** (not admin)   |

#### Step 3: User Experience

```
Power on → Connect to internet → Sign in with M365 → Auto-configures
 ↓
Joins Entra → Enrolls in Intune → Applies policies → Installs apps
 ↓
✅ Ready to use in 30–60 minutes — zero IT hands-on
```

> 💡 **Recommendation:** Begin registering Autopilot IDs for **all new device purchases** immediately. Retrofit existing devices as they are reimaged.

### 13.2 🔧 Operational Phase

Ongoing monitoring through Intune admin center:

| Dashboard                            | What to Monitor                    |
|:-------------------------------------|:-----------------------------------|
| Devices → Overview                   | Enrollment and compliance status   |
| Endpoint Security → Antivirus        | Defender status and alerts         |
| Reports → Device compliance          | Noncompliant device list           |
| Reports → Update status              | Patch compliance                   |

**Set up email notifications for:**

- 🔴 Noncompliance events
- 🔴 Enrollment failures
- 🔴 Defender threat detections

### 13.3 🗑️ Device Retirement

| Action     | What It Does                                     | When to Use                        |
|:-----------|:-------------------------------------------------|:-----------------------------------|
| **Retire** | Removes corporate data, policies, apps; leaves OS| Employee departure, device reuse   |
| **Wipe**   | Full factory reset — erases everything           | Device decommission or resale      |
| **Delete** | Removes device record from Intune                | After wipe/retire is confirmed     |

> ⛔ **Always Retire or Wipe BEFORE Delete.** Deleting a record without wiping leaves corporate data on the physical device.

---

## 📐 14. Operational Governance Model

### 14.1 Naming Standards

Consistent naming prevents confusion as policies scale.

```
┌─────────────────────────────────────────────────────────────┐
│  NAMING CONVENTION                                          │
├──────────┬──────────────────────────────────────────────────┤
│ Prefix   │ Purpose                                         │
├──────────┼──────────────────────────────────────────────────┤
│ SG-      │ Security Group                                  │
│ DG-      │ Device Group (dynamic or manual)                │
│ CP-      │ Compliance Policy                               │
│ CFG-     │ Configuration Profile                           │
│ UR-      │ Update Ring                                     │
│ AP-      │ Autopilot Profile                               │
│ CA-      │ Conditional Access Policy                       │
└──────────┴──────────────────────────────────────────────────┘
```

**Full naming reference:**

| Name                                | Type                |
|:------------------------------------|:--------------------|
| `SG-INTUNE-PILOT`                   | Security Group      |
| `SG-INTUNE-E3-USERS`               | Security Group      |
| `SG-INTUNE-F3-USERS`               | Security Group      |
| `SG-INTUNE-ALL-USERS`              | Security Group      |
| `SG-INTUNE-BREAKGLASS`             | Security Group      |
| `DG-Win11-Ready`                    | Device Group        |
| `CP-Windows-Compliance-Audit`       | Compliance Policy   |
| `CP-Windows-Compliance-Enforced`    | Compliance Policy   |
| `CFG-Windows-SecurityBaseline`      | Config Profile      |
| `UR-IT-Testing`                     | Update Ring         |
| `UR-Standard-Production`            | Update Ring         |
| `AP-Standard-UserDriven`            | Autopilot Profile   |
| `CA-Require-Compliant-Device`       | Conditional Access  |

### 14.2 Change Management

For a **single-administrator** environment:

- 📝 Document all policy changes with date, reason, and rollback plan
- 🧪 Test all changes on pilot group before production
- 📢 Notify affected users **48 hours** before disruptive changes
- ↩️ Maintain a rollback procedure for every enforced policy

---

## 📅 15. Recommended Deployment Order

| Step | Action                                | Timeline   | Dependencies              |
|:----:|:--------------------------------------|:-----------|:--------------------------|
| 1    | Foundation config + groups            | Week 1     | —                         |
| 2    | Pilot enrollment (5–10 devices)       | Week 1–2   | Step 1                    |
| 3    | Hardware inventory + Win11 report     | Week 2–3   | Step 2                    |
| 4    | Audit compliance policy               | Week 2     | Step 2                    |
| 5    | BitLocker policy + key escrow         | Week 3     | Step 2                    |
| 6    | **Verify recovery keys in Entra**     | Week 3–4   | Step 5                    |
| 7    | Security baseline (pilot)             | Week 3     | Step 2                    |
| 8    | Update rings (IT test + production)   | Week 4     | Step 2                    |
| 9    | Expand enrollment to all users        | Week 5–6   | Steps 4–8 stable          |
| 10   | Enforced compliance + BitLocker req   | Week 7–8   | Step 6 confirmed ✅        |
| 11   | Conditional Access (report-only)      | Week 9–10  | Step 10 stable, 90%+ ✅    |
| 12   | Conditional Access (enforced)         | Week 11–12 | Step 11 validated ✅       |
| 13   | Autopilot profiles for new devices    | Ongoing    | Step 1                    |
| 14   | Application deployment                | Ongoing    | Step 9                    |

```
WEEK  1    2    3    4    5    6    7    8    9   10   11   12+
      ├────┤
      │ Foundation + Pilot Enrollment
           ├─────────┤
           │ Audit Compliance + BitLocker + Baseline
                     ├─────────┤
                     │ Verify Escrow + Update Rings
                               ├─────────┤
                               │ Expand Enrollment
                                         ├─────────┤
                                         │ Enforce Compliance
                                                   ├─────────┤
                                                   │ Conditional Access
                                                             ├──────→
                                                             │ Autopilot + Apps
```

---

## ⚠️ 16. Common Pitfalls

| Pitfall                                                | Impact                              |
|:-------------------------------------------------------|:------------------------------------|
| Enabling Conditional Access before compliance is stable | 🔴 Locks users out of M365         |
| Requiring BitLocker without confirming key escrow       | 🔴 Risks permanent data loss       |
| Deploying M365 Apps to F3 users                        | 🟡 Deployment fails, error noise    |
| Skipping the pilot group                               | 🔴 Problems hit all users at once   |
| Mixing Hybrid + Entra Join without clear targeting      | 🟡 Creates enrollment conflicts    |
| Not excluding break-glass from Conditional Access       | 🔴 Locks out all admins            |
| Setting ASR rules to Block before Audit                 | 🟡 Breaks legitimate apps          |
| Using dynamic groups for Win11 readiness                | 🟡 OS filter can't validate HW     |
| Forgetting user notification before MFA/compliance      | 🟡 Help desk overload              |

---

## ✅ 17. Reference Checklist

### 🔧 Foundation

- [ ] Intune MDM authority confirmed
- [ ] MDM user scope configured
- [ ] Security groups created (pilot, E3, F3, all, break-glass)
- [ ] No conflicting policies or Conditional Access rules

### 📲 Enrollment

- [ ] Pilot devices enrolled (mix of E3 and F3)
- [ ] Enrollment verified from multiple sites
- [ ] Devices appearing in Intune admin center

### 📊 Readiness

- [ ] Hardware inventory reviewed
- [ ] Windows 11 readiness report exported
- [ ] Win11-Ready and Not-Ready groups populated

### 🛡️ Security

- [ ] Audit compliance policy deployed to pilot
- [ ] BitLocker policy deployed to pilot
- [ ] **Recovery keys confirmed in Entra** for pilot devices
- [ ] Security baseline deployed to pilot
- [ ] Update rings deployed (IT test + production)

### 🔒 Enforcement

- [ ] Compliance policy switched to enforced
- [ ] BitLocker required (after key escrow confirmed)
- [ ] Conditional Access in report-only mode
- [ ] Conditional Access enforced (after validation)

### ♻️ Lifecycle

- [ ] Autopilot device IDs registered for new hardware
- [ ] Autopilot deployment profile created
- [ ] Core applications packaged and deployed
- [ ] Retirement workflow documented

---

## 📜 Closing Notes

This architecture scales from **50 devices to 500+** without structural changes. The phased approach ensures no policy is enforced before its impact is understood.

> 🎯 **For a single-administrator environment, the most important principle is:**
> **Never enforce a policy you haven't validated on a pilot group for at least two weeks.**

```
╔═══════════════════════════════════════════════════════════════════╗
║  Audit → Stabilize → Enforce → Automate → Expand               ║
╚═══════════════════════════════════════════════════════════════════╝
```

---

*End of Document.*
