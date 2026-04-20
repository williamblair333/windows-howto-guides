# Flameshot — Complete Windows Installation & Configuration Guide

> **Flameshot** is a free, open-source, cross-platform screenshot tool with built-in annotation,
> clipboard integration, and Imgur upload. This guide covers installation, configuration,
> multi-monitor fixes, hotkey setup, CLI usage, and replacing Windows Snipping Tool.

---

## Table of Contents

- [1. System Requirements](#1-system-requirements)
- [2. Download](#2-download)
- [3. Installation Methods](#3-installation-methods)
  - [3a. MSI Installer (Recommended)](#3a-msi-installer-recommended)
  - [3b. Portable (No Install)](#3b-portable-no-install)
  - [3c. Package Managers](#3c-package-managers)
- [4. First Launch & System Tray](#4-first-launch--system-tray)
- [5. Multi-Monitor Fix (Critical)](#5-multi-monitor-fix-critical)
  - [Fix 1 — DPI Scaling Override](#fix-1--dpi-scaling-override)
  - [Fix 2 — Match Display Scaling](#fix-2--match-display-scaling)
  - [Fix 3 — CLI Per-Monitor Capture](#fix-3--cli-per-monitor-capture)
  - [Fix 4 — Pre-Release Build with Native Fix](#fix-4--pre-release-build-with-native-fix)
  - [Fix 5 — Flameshot 14.0 RC1 (New Monitor Workflow)](#fix-5--flameshot-140-rc1-new-monitor-workflow)
- [6. Replace Windows Snipping Tool](#6-replace-windows-snipping-tool)
  - [Method A — Default App Association](#method-a--default-app-association)
  - [Method B — Registry Protocol Handler](#method-b--registry-protocol-handler)
- [7. Hotkey Configuration](#7-hotkey-configuration)
  - [Built-In Global Hotkey](#built-in-global-hotkey)
  - [Custom Hotkeys via Windows Settings](#custom-hotkeys-via-windows-settings)
- [8. GUI Configuration](#8-gui-configuration)
- [9. CLI Reference (Windows)](#9-cli-reference-windows)
  - [Important: Use flameshot-cli.exe](#important-use-flameshot-cliexe)
  - [Capture Modes](#capture-modes)
  - [Final Actions](#final-actions)
  - [Configuration via CLI](#configuration-via-cli)
- [10. In-App Keyboard Shortcuts](#10-in-app-keyboard-shortcuts)
- [11. Configuration File](#11-configuration-file)
- [12. Auto-Start on Boot](#12-auto-start-on-boot)
- [13. Troubleshooting](#13-troubleshooting)
- [14. Uninstallation](#14-uninstallation)
- [15. Additional Resources](#15-additional-resources)

---

## 1. System Requirements

| Requirement       | Detail                                      |
|:------------------|:--------------------------------------------|
| **OS**            | Windows 7 / 8 / 10 / 11 (64-bit)           |
| **Architecture**  | x86_64 only                                 |
| **Disk Space**    | ~25 MB                                      |
| **Dependencies**  | None (Qt is bundled)                         |
| **License**       | GPLv3 — Free and Open Source                |

---

## 2. Download

Always download from **official sources only**:

| Source                   | URL                                                              |
|:-------------------------|:-----------------------------------------------------------------|
| **GitHub Releases**      | <https://github.com/flameshot-org/flameshot/releases>            |
| **Official Website**     | <https://flameshot.org/>                                         |

**Current Versions:**

- **Stable:** `v13.3.0` — `Flameshot-13.3.0-win64.msi`
- **Release Candidate:** `v14.0.0 RC1` — Includes native multi-monitor rework

**Verify Integrity (v13.3.0):**

```
SHA256: 37ca5916450fab003fb3c64eacd01d103d11d122c30bade6af144d4b0874df66
File:   Flameshot-13.3.0-win64.msi
```

> **Tip:** The stable v13.3.0 has a known multi-monitor bug. If you have a multi-monitor setup,
> download the **portable fix build** from PR #4498 (see [Section 5, Fix 4](#fix-4--pre-release-portable-build-with-native-fix-recommended))
> or go straight to **v14.0 RC1** which includes the same fix.

---

## 3. Installation Methods

### 3a. MSI Installer (Recommended)

1. Download `Flameshot-13.3.0-win64.msi` from GitHub Releases
2. Double-click the `.msi` file
3. Follow the installer prompts (default path: `C:\Program Files\Flameshot\`)
4. Launch from Start Menu or System Tray

**Default install paths:**

```
Executable:  C:\Program Files\Flameshot\bin\flameshot.exe
CLI Wrapper: C:\Program Files\Flameshot\bin\flameshot-cli.exe
```

### 3b. Portable (No Install)

1. Download the **Portable** `.zip` from GitHub Releases
2. Extract to any folder (e.g., `C:\Tools\Flameshot\`)
3. Run `flameshot.exe` directly
4. Configuration is stored in `flameshot.ini` next to the executable

> **Portable mode** is ideal for USB drives, locked-down machines, or testing new versions
> side-by-side with a stable install.

### 3c. Package Managers

**Scoop:**

```powershell
scoop install flameshot
```

**Chocolatey:**

```powershell
choco install flameshot
```

**winget:**

```powershell
winget install flameshot
```

---

## 4. First Launch & System Tray

After installation:

1. Launch **Flameshot** from the Start Menu
2. A tray icon appears in the system tray (bottom-right taskbar)
3. **Right-click** the tray icon to access:
   - **Configuration** — Opens the settings GUI
   - **Information** — Shows version and all keyboard shortcuts
4. **Left-click** or press `PrtSc` to begin a capture

> If the tray icon doesn't appear, click the **↑** arrow in the taskbar to check the overflow area.
> You can pin it by dragging it onto the visible taskbar.

---

## 5. Multi-Monitor Fix (Critical)

⚠ **Flameshot has a well-documented multi-monitor bug** affecting both Windows and Linux.
Symptoms include squished/shifted capture areas, black borders, missing monitors, and
incorrect region mapping. This has been tracked across multiple GitHub issues (#1184, #2930,
#4152, #4259, #4385).

Apply these fixes **in order** — stop when your setup works correctly.
Fixes 1–3 are quick workarounds; **Fix 4 is the recommended solution** that addresses
the root cause at the application level.

---

### Fix 1 — DPI Scaling Override

⚠️ **May not resolve the issue** — commonly suggested but did not fix multi-monitor capture
problems in testing. Try it first as it's non-destructive, but expect to need Fix 4.

1. Navigate to the Flameshot executable:
   ```
   C:\Program Files\Flameshot\bin\flameshot.exe
   ```
2. **Right-click** → **Properties**
3. Go to the **Compatibility** tab
4. Click **"Change high DPI settings"**
5. Under **High DPI scaling override**:
   - ☑ Check **"Override high DPI scaling behavior"**
   - Set **"Scaling performed by:"** → **Application**
6. Click **OK** → **Apply**
7. **Restart Flameshot** (close from tray, relaunch)

---

### Fix 2 — Match Display Scaling

⚠️ **May not resolve the issue** — reduces variables but did not fix the problem in testing
even when combined with Fix 1. Worth trying as it's easily reversible.

1. Open **Settings** → **System** → **Display**
2. Click each monitor and check the **Scale** percentage
3. **Set all monitors to the same scale factor**
   - e.g., all at `100%`, or all at `125%`, or all at `150%`
4. If monitors have different native resolutions, pick the scale that works best
   as a compromise and adjust resolution if needed

> **Why this works:** Flameshot calculates the virtual desktop canvas using Qt's
> DPI-aware geometry. Mixed scaling (e.g., 100% + 125%) causes Qt to miscompute
> the capture region boundaries.

---

### Fix 3 — CLI Per-Monitor Capture

If the GUI capture remains broken, bypass it entirely with targeted CLI commands:

```powershell
# Capture primary monitor (index 0)
& "C:\Program Files\Flameshot\bin\flameshot.exe" screen --number 0

# Capture secondary monitor (index 1)
& "C:\Program Files\Flameshot\bin\flameshot.exe" screen --number 1

# Capture primary monitor and copy to clipboard
& "C:\Program Files\Flameshot\bin\flameshot.exe" screen --number 0 --clipboard

# Capture primary monitor and save to file
& "C:\Program Files\Flameshot\bin\flameshot.exe" screen --number 0 --path "$env:USERPROFILE\Pictures\Screenshots"
```

> **Tip:** Bind these commands to custom hotkeys using AutoHotkey or
> Windows Settings → Keyboard Shortcuts for a seamless workflow.

---

### Fix 4 — Pre-Release Portable Build with Native Fix (Recommended)

✅ **Confirmed working** — this build resolved multi-monitor capture issues on a Windows 11
dual-monitor setup where Fix 1 and Fix 2 both failed. Multiple users on the PR have
confirmed it working with mixed DPI, mixed resolutions, and mixed orientations.

PR [#4498](https://github.com/flameshot-org/flameshot/pull/4498) contains a native
multi-monitor fix that changes Flameshot to screenshot one monitor at a time (matching
macOS behavior), eliminating the DPI/scaling calculation bugs entirely.

**How to download:**

1. **Sign into GitHub** (required to download CI artifacts)
2. Go to: <https://github.com/flameshot-org/flameshot/actions/runs/21695624758>
3. Scroll to the **Artifacts** section at the bottom of the page
4. Download: **`flameshot-v13.3.0+git46.d4987a87-artifact-win-x64-portable`**
5. Unzip to a folder like `C:\Tools\Flameshot-fix\`
6. Run `flameshot.exe` from that folder — fully portable, no install needed

> **Note:** This build introduces a new workflow — you select which monitor to capture
> first via a selection dialog, then the capture overlay appears on that monitor only.
> A minor cosmetic white border (~1-2px) may appear on the smaller monitor's edge but
> does not affect the actual captured screenshot.

> **If the artifact has expired** (GitHub retains CI artifacts for 90 days), use
> [Fix 5 — Flameshot 14.0 RC1](#fix-5--flameshot-140-rc1-new-monitor-workflow) instead,
> which includes the same fix merged into a release build.

---

### Fix 5 — Flameshot 14.0 RC1 (New Monitor Workflow)

Version 14.0 **completely reworked the multi-monitor capture model**:

- Users are now prompted to **select which monitor** to capture instead of spanning all monitors
- HiDPI region scaling bugs are fixed
- New **"Capture active monitor"** option skips the selection dialog and captures whichever
  monitor the cursor is on
- Fractional scaling support added

**To try it:**

1. Download from [GitHub Releases](https://github.com/flameshot-org/flameshot/releases) → `v14.0.0-rc1`
2. Install the MSI or use the portable version
3. In **Settings → General**, optionally enable:
   - ☑ **"Capture active monitor (skip monitor selection)"** — auto-captures the monitor under your cursor

> ⚠ This is a **Release Candidate** — not yet stable. Test before relying on it for production work.

---

## 6. Replace Windows Snipping Tool

Make Flameshot the default handler for `Win + Shift + S` and `PrtSc`.

> ⚠️ **Windows Update Warning:** Windows Update periodically reinstates default app
> associations, startup entries, and system hotkey bindings. Method A alone will not
> survive a feature update. Use **Method C** to permanently disable the system hook and
> **Method D** to prevent Snipping Tool from being reinstalled. See also
> [Section 13 — Troubleshooting](#13-troubleshooting) for the "disappeared after update" fix.

### Method A — Default App Association

1. Press `Win + Shift + S` — Windows will show a prompt asking which tool to use
2. Select **Flameshot**
3. Choose **"Always"**

If no prompt appears:

1. Open **Settings** → **Apps** → **Default Apps**
2. Scroll to **"Choose defaults by link type"**
3. Search for **`MS-SCREENCLIP`**
4. Select **Flameshot**

> **Limitation:** This association can be silently reset by Windows Update. Pair with
> Method C to suppress the system hook at a lower level.

### Method B — Registry Protocol Handler

Save the following as `flameshot-default.reg` and merge it:

```registry
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Flameshot\Capabilities\URLAssociations]
"ms-screenclip"="Flameshot"

[HKEY_LOCAL_MACHINE\SOFTWARE\RegisteredApplications]
"Flameshot"="SOFTWARE\\Flameshot\\Capabilities"

[HKEY_CLASSES_ROOT\Flameshot\Shell\Open\command]
@="\"C:\\Program Files\\Flameshot\\bin\\flameshot.exe\" gui"
```

Then follow Method A above to select Flameshot as the default for `MS-SCREENCLIP`.

> **To revert:** Delete the registry keys above and set Snipping Tool as the default in
> Settings → Default Apps.

### Method C — Disable Win+Shift+S System Hook (Recommended)

This disables the `Win+Shift+S` key at the Explorer level, freeing it for AutoHotkey
to claim. This survives most Windows Updates.

```powershell
Set-ItemProperty `
  -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
  -Name "DisabledHotkeys" -Value "S" -Type String
```

> **If `DisabledHotkeys` already has a value**, append `S` to the existing string rather
> than replacing it (e.g., if it contains `D`, set it to `DS`).

A **restart or logoff/logon** is required for the change to take effect.

To revert:
```powershell
Remove-ItemProperty `
  -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
  -Name "DisabledHotkeys" -ErrorAction SilentlyContinue
```

### Method D — Remove Snipping Tool (Prevents Reinstall)

Removing just the app package is not enough — Windows re-provisions it on feature updates
unless the provisioned package is also removed.

```powershell
# Remove for current user
Get-AppxPackage *ScreenSketch* | Remove-AppxPackage

# Remove provisioned package (prevents reinstall on feature updates)
Get-AppxProvisionedPackage -Online |
  Where-Object DisplayName -like "*ScreenSketch*" |
  Remove-AppxProvisionedPackage -Online
```

> ⚠️ Run both commands. The first alone is insufficient — Windows will silently reinstall
> Snipping Tool on the next feature update if the provisioned package remains.

---

## 7. Hotkey Configuration

### Built-In Global Hotkey

Flameshot registers `PrtSc` (Print Screen) as its global hotkey on Windows by default.

> **v14.0+** adds support for configurable global hotkeys and PrtSc conflict detection/auto-fix.

### Custom Hotkeys via Windows Settings

If `PrtSc` conflicts with other software or your keyboard lacks the key:

1. **Settings** → **Accessibility** → **Keyboard**
2. Turn **OFF** "Use the Print Screen button to open screen snipping"
3. Create a custom shortcut (or use AutoHotkey):

### Win+Shift+S via AutoHotkey (Recommended)

This is the most reliable way to bind `Win+Shift+S` to Flameshot on Windows. First complete
[Section 6, Method C](#method-c--disable-winshifts-system-hook-recommended) to free the
key from Explorer, then set up AutoHotkey:

1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Create `flameshot_hotkey.ahk` with the contents below
3. Add a **shortcut to this script** in your startup folder (`shell:startup`) **and** register
   it in Task Scheduler (see [Section 12, Method 4](#method-4--task-scheduler-enterprise)) —
   using both ensures it survives Windows Update

> ⚠️ **Windows Update Warning:** AHK scripts in the startup folder can be removed or
> bypassed after a feature update. The Task Scheduler entry is more resilient — register
> the AHK script launch there as a backup.

**AutoHotkey v2 Example (`flameshot_hotkey.ahk`):**

```autohotkey
; Win+Shift+S → Flameshot GUI capture (replaces Snipping Tool)
; Requires: DisabledHotkeys registry key set to "S" (see Section 6, Method C)
#+s::
{
    Run '"C:\Program Files\Flameshot\bin\flameshot.exe" gui'
}

; Ctrl+Shift+F → Full screen capture to clipboard
^+f::
{
    Run '"C:\Program Files\Flameshot\bin\flameshot.exe" full --clipboard'
}

; Ctrl+Shift+1 → Capture monitor 1
^+1::
{
    Run '"C:\Program Files\Flameshot\bin\flameshot.exe" screen --number 0 --clipboard'
}

; Ctrl+Shift+2 → Capture monitor 2
^+2::
{
    Run '"C:\Program Files\Flameshot\bin\flameshot.exe" screen --number 1 --clipboard'
}
```

> **AHK v1 users:** Replace `{ Run '...' }` blocks with `Run, ...` followed by `return`.
> The examples above use **v2 syntax** which is the current version.

---

## 8. GUI Configuration

Access via **right-click tray icon → Configuration**, or run:

```powershell
& "C:\Program Files\Flameshot\bin\flameshot.exe" config
```

### Interface Tab

- Select which annotation tools appear around the capture area
- Reorder tool buttons
- Set tool colors and thickness

### Filename Editor Tab

- Configure automatic screenshot naming pattern
- Use date/time tokens: `%Y-%m-%d_%H-%M-%S`
- Example: `screenshot_2026-04-10_14-30-22.png`

### General Tab

| Setting                        | Recommendation                |
|:-------------------------------|:------------------------------|
| Show desktop notifications     | ✅ Enable                     |
| Show tray icon                 | ✅ Enable                     |
| Launch at startup              | ✅ Enable (see Section 12)    |
| Auto-copy to clipboard         | ✅ Enable                     |
| Default save path              | `%USERPROFILE%\Pictures\Screenshots` |
| Capture active monitor*        | ✅ Enable (v14.0+ only)       |

---

## 9. CLI Reference (Windows)

### Important: Use flameshot-cli.exe

On Windows, `flameshot.exe` is a **GUI application** — it does not output text to the console.
For any CLI interaction that requires console output (help text, version info, diagnostics),
use `flameshot-cli.exe` instead:

```powershell
& "C:\Program Files\Flameshot\bin\flameshot-cli.exe" --help
& "C:\Program Files\Flameshot\bin\flameshot-cli.exe" --version
```

> For launching captures, `flameshot.exe` works fine — `flameshot-cli.exe` is only
> needed when you want to **read stdout** (help, version, geometry output).

### Capture Modes

```powershell
# Interactive GUI capture (drag-select region)
flameshot gui

# Full-screen capture (all monitors)
flameshot full

# Capture specific monitor
flameshot screen --number 0

# Delayed capture (2 second delay)
flameshot gui --delay 2000

# Capture specific region (WxH+X+Y)
flameshot gui --region 800x600+100+100

# Repeat last capture region
flameshot gui --last-region

# Capture and immediately accept selection on mouse release
flameshot gui --accept-on-select
```

### Final Actions

Final actions define what happens **after** the screenshot is captured. When specified,
they replace the GUI toolbar buttons with a single "Accept" button.

```powershell
# Save to specific folder
flameshot gui --path "$env:USERPROFILE\Pictures\Screenshots"

# Copy to clipboard
flameshot gui --clipboard

# Upload to Imgur
flameshot gui --upload

# Pin screenshot on screen (stays on top)
flameshot gui --pin

# Combine multiple actions
flameshot gui --clipboard --path "$env:USERPROFILE\Pictures\Screenshots" --pin

# Print capture geometry (WxH+X+Y) — useful for scripting
flameshot gui --print-geometry
```

### Configuration via CLI

```powershell
# Open the configuration GUI
flameshot config

# Set default save path
flameshot config --savepath "$env:USERPROFILE\Pictures\Screenshots"

# Set filename pattern
flameshot config --filename "screenshot_%Y-%m-%d_%H-%M-%S"

# Enable/disable tray icon
flameshot config --trayicon true

# Enable/disable desktop notifications
flameshot config --showdesktopnotification true

# Enable/disable auto-copy to clipboard
flameshot config --autocopytoclipboard true
```

---

## 10. In-App Keyboard Shortcuts

These shortcuts are active **during a capture session** (after pressing PrtSc or launching GUI):

| Shortcut            | Action                                         |
|:--------------------|:-----------------------------------------------|
| `←` `→` `↑` `↓`   | Move selection 1px                             |
| `Shift` + Arrow     | Resize selection 1px                           |
| `Shift` + Drag corner | Mirror resize from opposite corner          |
| `Ctrl + C`          | Copy to clipboard                              |
| `Ctrl + S`          | Save to file                                   |
| `Ctrl + Z`          | Undo last annotation                           |
| `Ctrl + Shift + Z`  | Redo                                           |
| `Enter`             | Upload to Imgur                                |
| `Esc`               | Cancel / exit capture                          |
| `Space`             | Toggle side panel (color, size)                |
| `Right Click`       | Show color picker / tool options               |
| `Scroll Wheel`      | Adjust tool thickness                          |

> View the complete shortcut list: **Right-click tray icon → Information**

---

## 11. Configuration File

Flameshot stores settings in an INI file:

**Installed version:**

```
%APPDATA%\flameshot\flameshot.ini
```

**Portable version:**

```
<flameshot-directory>\flameshot.ini
```

### Example Configuration

```ini
[General]
savePath=C:/Users/William/Pictures/Screenshots
showDesktopNotification=true
showTrayIcon=true
autoCloseIdleDaemon=false
allowMultipleGuiInstances=false
savePathFixed=false
filenamePattern=screenshot_%Y-%m-%d_%H-%M-%S
disabledTrayIcon=false
autocopytoclipboard=true
startupLaunch=true
showStartupLaunchMessage=false

[Shortcuts]
TYPE_ARROW=A
TYPE_CIRCLE=C
TYPE_CIRCLECOUNT=
TYPE_COPY=Ctrl+C
TYPE_DRAWER=D
TYPE_EXIT=Esc
TYPE_IMAGEUPLOADER=Return
TYPE_MARKER=M
TYPE_MOVESELECTION=
TYPE_OPEN_APP=
TYPE_PENCIL=P
TYPE_PIN=
TYPE_PIXELATE=B
TYPE_REDO=Ctrl+Shift+Z
TYPE_RESIZE_DOWN=Shift+Down
TYPE_RESIZE_LEFT=Shift+Left
TYPE_RESIZE_RIGHT=Shift+Right
TYPE_RESIZE_UP=Shift+Up
TYPE_RECTANGLE=R
TYPE_SAVE=Ctrl+S
TYPE_SELECTION=S
TYPE_TEXT=T
TYPE_TOGGLE_PANEL=Space
TYPE_UNDO=Ctrl+Z
```

> **Backup tip:** Copy `flameshot.ini` before making changes. Restore by replacing the file.

---

## 12. Auto-Start on Boot

> ⚠️ **Windows Update Warning:** Feature updates can wipe startup folder entries and
> `HKCU\...\Run` registry keys. **Task Scheduler (Method 4) is the most update-resistant
> method** and is strongly recommended, especially in managed or frequently-updated
> environments. Use it as the primary method, not a fallback.

### Method 1 — Flameshot Settings

1. Right-click tray icon → **Configuration**
2. **General** tab → ☑ **"Launch at startup"**

> This writes a `HKCU\...\Run` registry entry — may not survive Windows feature updates.

### Method 2 — Startup Folder

1. Press `Win + R` → type `shell:startup` → Enter
2. Create a shortcut to:
   ```
   "C:\Program Files\Flameshot\bin\flameshot.exe"
   ```

> May not survive Windows feature updates. Use Method 4 for better persistence.

### Method 3 — Registry (Scriptable)

```powershell
# Enable auto-start
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "Flameshot" `
    -Value '"C:\Program Files\Flameshot\bin\flameshot.exe"' `
    -PropertyType String -Force

# Disable auto-start (reversal)
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "Flameshot" -ErrorAction SilentlyContinue
```

> May not survive Windows feature updates. Use Method 4 for better persistence.

### Method 4 — Task Scheduler (Recommended — Most Update-Resistant)

Task Scheduler entries survive Windows feature updates where the startup folder and
`Run` registry keys do not. Use `-RunLevel Highest` to avoid UAC prompts on launch.

```powershell
$Action  = New-ScheduledTaskAction -Execute "C:\Program Files\Flameshot\bin\flameshot.exe"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "Flameshot" `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -RunLevel Highest `
    -Description "Launch Flameshot screenshot tool at logon" `
    -Force
```

To also launch the AutoHotkey script at logon via Task Scheduler:

```powershell
$AHKAction = New-ScheduledTaskAction `
    -Execute "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" `
    -Argument '"C:\Users\<YourUser>\flameshot_hotkey.ahk"'
$Trigger  = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "Flameshot AHK Hotkeys" `
    -Action $AHKAction `
    -Trigger $Trigger `
    -Settings $Settings `
    -RunLevel Highest `
    -Description "Load Flameshot Win+Shift+S hotkey via AutoHotkey" `
    -Force
```

> Replace `<YourUser>` with your actual username and verify the AutoHotkey path matches
> your installed version (v1 path differs from v2).

---

## 13. Troubleshooting

### Flameshot doesn't appear in tray

- Check the **overflow area** (↑ arrow in taskbar)
- Ensure Flameshot is running (Task Manager → `flameshot.exe`)
- Try launching from command line: `flameshot.exe`

### PrtSc doesn't trigger Flameshot

- **Settings** → **Accessibility** → **Keyboard** → Turn OFF
  "Use the Print Screen button to open screen snipping"
- Ensure no other screenshot tool is capturing the hotkey
- v14.0+ includes PrtSc conflict detection and auto-fix

### Capture area is shifted / squished / black borders

- Apply [Multi-Monitor Fixes](#5-multi-monitor-fix-critical) (Section 5)
- Fix 1 + Fix 2 together resolve the majority of cases

### Flameshot only captures one monitor after RDP/remote session

- Flameshot caches the monitor layout at launch
- **Fix:** Restart Flameshot after reconnecting to the physical multi-monitor setup
  ```powershell
  Stop-Process -Name flameshot -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
  & "C:\Program Files\Flameshot\bin\flameshot.exe"
  ```

### Flameshot setup disappeared after Windows Update

Windows feature updates can silently reset all of the following:

- Default app associations (`MS-SCREENCLIP` → Snipping Tool restored)
- `HKCU\...\Run` startup registry entries (Flameshot tray no longer starts)
- Startup folder shortcuts
- AHK script execution from startup folder

**Recovery checklist** — run in order:

```powershell
# 1. Re-register Task Scheduler entries (Flameshot + AHK)
#    See Section 12, Method 4 — paste those commands again

# 2. Re-disable Win+Shift+S system hook
Set-ItemProperty `
  -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
  -Name "DisabledHotkeys" -Value "S" -Type String

# 3. Re-remove Snipping Tool provisioned package if it was reinstalled
Get-AppxPackage *ScreenSketch* | Remove-AppxPackage
Get-AppxProvisionedPackage -Online |
  Where-Object DisplayName -like "*ScreenSketch*" |
  Remove-AppxProvisionedPackage -Online

# 4. Log off and back on (or restart) to apply hotkey change
```

**Prevention:** The Task Scheduler method (Section 12, Method 4) and the `DisabledHotkeys`
registry key are the most durable. The provisioned package removal is the only reliable way
to prevent Snipping Tool from coming back after a feature update.



- Fixed in v14.0 RC1 (forced PNG clipboard format; JPG caused compatibility issues)
- Workaround on v13.x: save to file, then copy from file

### Console output not showing (--help, --version)

- Use `flameshot-cli.exe` instead of `flameshot.exe` for any command that
  requires console output

---

## 14. Uninstallation

### MSI Install

```powershell
# Via Settings
# Settings → Apps → Installed Apps → Flameshot → Uninstall

# Via PowerShell
Get-Package -Name "Flameshot*" | Uninstall-Package
```

### Portable

Delete the extracted folder. Optionally remove the config file:

```powershell
Remove-Item "$env:APPDATA\flameshot" -Recurse -Force
```

### Clean Up (Both Methods)

```powershell
# Remove auto-start entry
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name "Flameshot" -ErrorAction SilentlyContinue

# Remove configuration
Remove-Item "$env:APPDATA\flameshot" -Recurse -Force -ErrorAction SilentlyContinue

# Remove registry handler (if set up)
Remove-Item "HKCR:\Flameshot" -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\RegisteredApplications" `
    -Name "Flameshot" -ErrorAction SilentlyContinue
Remove-Item "HKLM:\SOFTWARE\Flameshot" -Recurse -Force -ErrorAction SilentlyContinue
```

---

## 15. Additional Resources

| Resource             | URL                                                                   |
|:---------------------|:----------------------------------------------------------------------|
| Official Website     | <https://flameshot.org/>                                              |
| GitHub Repository    | <https://github.com/flameshot-org/flameshot>                          |
| All Releases         | <https://github.com/flameshot-org/flameshot/releases>                 |
| CLI Documentation    | <https://flameshot.org/docs/advanced/commandline-options/>             |
| Key Bindings         | <https://flameshot.org/docs/guide/key-bindings/>                      |
| Windows Help         | <https://flameshot.org/docs/guide/windows-help/>                      |
| Configuration Guide  | <https://flameshot.org/docs/advanced/configuration/>                  |
| Multi-Monitor PR     | <https://github.com/flameshot-org/flameshot/pull/4498>                |
| Bug Tracker          | <https://github.com/flameshot-org/flameshot/issues>                   |

---

> **Document Version:** 1.2 — April 2026
> **Covers:** Flameshot v13.3.0 (stable), PR #4498 portable fix build, and v14.0.0 RC1
> **Author:** Windows Systems Engineering Reference
