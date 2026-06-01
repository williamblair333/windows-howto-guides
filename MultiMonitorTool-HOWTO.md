# MultiMonitorTool — Practical HOWTO

> A field guide to **NirSoft MultiMonitorTool v2.21** for enabling, disabling, arranging, scaling, and scripting multiple monitors on Windows (XP → 11). No installation required — it's a single portable `.exe`.

---

## Table of Contents

1. [What It Does](#1-what-it-does)
2. [Quick Start](#2-quick-start)
3. [Core Concept: How to Name a Monitor](#3-core-concept-how-to-name-a-monitor)
4. [The "Hardwire a Monitor to a Number" Problem](#4-the-hardwire-a-monitor-to-a-number-problem)
5. [GUI Workflows](#5-gui-workflows)
6. [Command-Line Reference](#6-command-line-reference)
7. [Recipes](#7-recipes)
8. [Windows 11 24H2 Gotchas](#8-windows-11-24h2-gotchas)
9. [Troubleshooting](#9-troubleshooting)
10. [Appendix](#10-appendix)

---

## 1. What It Does

MultiMonitorTool covers four jobs that Windows handles poorly or not at all:

| Capability | GUI | CLI | Notes |
|---|:---:|:---:|---|
| Enable / disable monitors | ✅ | ✅ | Survives reboots only via saved config |
| Set primary monitor | ✅ | ✅ | `Ctrl+F9` / `/SetPrimary` |
| Save & restore full layout | ✅ | ✅ | Resolution, depth, **position**, orientation |
| Set resolution / orientation / scale | ✅ | ✅ | `/setmax`, `/SetOrientation`, `/SetScale` |
| Move windows between monitors | ✅ | ✅ | By process, title, or window class |
| Turn panels off/on (DDC/CI) | ✅ | ✅ | Hardware-dependent |
| Live preview of any monitor | ✅ | ✅ | `F2` / `/PreviewOnly` |

> ⚠️ **Only useful for *extended* desktops.** If your monitors mirror the same content, this tool does nothing for you.

---

## 2. Quick Start

```text
1. Download the x64 build from nirsoft.net
2. Unzip MultiMonitorTool.exe to a permanent folder (e.g. C:\Tools\MMT\)
3. Double-click to run — no install, no DLLs
4. Upper pane = monitors, lower pane = windows on the selected monitor
```

First thing worth doing — **capture your current good layout** so you can always get back to it:

```bat
MultiMonitorTool.exe /SaveConfig "C:\Tools\MMT\baseline.cfg"
```

---

## 3. Core Concept: How to Name a Monitor

Every command-line option takes a `<Monitor>` argument. You have **six** ways to specify it, listed here from *least* to *most* stable:

| Identifier | Example | Stability | Where to find it |
|---|---|---|---|
| Monitor **Number** | `2` | ❌ Reorders on reboot/GPU change | The digit in `\\.\DISPLAYn` |
| Monitor **Name** | `\\.\DISPLAY2` | ❌ Same problem | `Name` column |
| `Primary` keyword | `Primary` | ⚠️ Follows whatever is primary | — |
| **Short Monitor ID** | `GSM59A4` | ✅ Tied to hardware model | `Short Monitor ID` column |
| **Monitor ID** | `MONITOR\GSM59A4\{...}\0008` | ✅ Tied to hardware | `Monitor ID` column |
| **Serial Number** | `334DFRGV451` | ✅✅ Unique per physical unit | `Monitor Serial Number` column |

> 💡 **Rule of thumb:** for anything you want to *survive a reboot*, address monitors by **Serial Number** (most precise) or **Monitor ID**. Only use `\\.\DISPLAYn` / numbers for throwaway one-off commands.

To reveal the hidden columns, right-click the header in the GUI and enable *Monitor ID*, *Short Monitor ID*, and *Monitor Serial Number*.

---

## 4. The "Hardwire a Monitor to a Number" Problem

Windows assigns `1`/`2`/`3` dynamically — they shuffle after reboots, driver updates, and cable swaps. MultiMonitorTool **cannot rename a physical monitor to a fixed number**, but it solves the underlying goal two ways:

### Option A — Lock the layout, restore it on login

1. Arrange everything perfectly in Windows Display settings.
2. Save it:
   ```bat
   MultiMonitorTool.exe /SaveConfig "C:\Tools\MMT\layout.cfg"
   ```
3. Make the saved config match monitors by **hardware**, not slot:
   - GUI → **Options** → enable **`Use Monitor ID In Load Config`** *(on by default)*
   - GUI → **Options** → enable **`Use Serial Number In Load Config`** for even tighter matching
4. Re-apply automatically at login (Task Scheduler → *At log on*):
   ```bat
   MultiMonitorTool.exe /LoadConfig "C:\Tools\MMT\layout.cfg"
   ```

### Option B — Set positions explicitly by serial number

Bypass config files entirely and pin coordinates to physical units:

```bat
MultiMonitorTool.exe /SetMonitors ^
  "Name=SERIAL_OF_LEFT  PositionX=0    PositionY=0 Primary=1" ^
  "Name=SERIAL_OF_MID   PositionX=1920 PositionY=0" ^
  "Name=SERIAL_OF_RIGHT PositionX=3840 PositionY=0"
```

> 📌 **The takeaway:** you don't pin the *number* — you pin the *position and identity*. Generate the exact command for your current setup with **Edit → Copy /SetMonitors Command** (set the naming mode to *Serial Number* first under **Options → Copy /SetMonitors Command Mode**).

---

## 5. GUI Workflows

### Hotkeys you'll actually use

| Action | Shortcut |
|---|---|
| Disable selected monitor(s) | `Ctrl+F6` |
| Enable selected monitor(s) | `Ctrl+F7` |
| Disable/Enable toggle | `Ctrl+F8` |
| Set as primary | `Ctrl+F9` |
| Save monitors configuration | `Ctrl+Shift+S` |
| Load monitors configuration | `Ctrl+Shift+L` |
| Toggle preview window | `F2` |
| Move all windows → primary | `Ctrl+Shift+F1` |
| Advanced options | `Ctrl+O` |

### Moving stray windows back

Lower pane shows windows on the selected monitor. Select one or more, then:
- **Move Window To Next Monitor**, or
- **Move Window To Primary Monitor**

### Preview window

Press `F2`, select a monitor in the upper pane. Useful when a non-primary panel is powered off but you still need to see what's on it. Set the refresh rate in **Advanced Options** (`Ctrl+O`) — drop it to ~50 ms on a fast machine for near-real-time.

> 🎡 *Easter egg:* size the preview window to just under a full monitor and point it at that same monitor — you get the infinite "window-in-a-window" recursion.

---

## 6. Command-Line Reference

All commands run silently with no UI. `<Monitors>` accepts one or several space-separated identifiers (see [§3](#3-core-concept-how-to-name-a-monitor)).

### Enable / Disable

```bat
MultiMonitorTool.exe /disable 1
MultiMonitorTool.exe /disable \\.\DISPLAY3
MultiMonitorTool.exe /disable 1 2 3            :: multiple at once
MultiMonitorTool.exe /enable 3 2
MultiMonitorTool.exe /switch \\.\DISPLAY2      :: toggle state
MultiMonitorTool.exe /EnableAtPosition "\\.\DISPLAY2" 1920 0
```

> 🩹 If `/enable` misplaces a monitor on a 3+ panel system, use **`/EnableAtPosition`** to force its coordinates.

### Primary monitor

```bat
MultiMonitorTool.exe /SetPrimary \\.\DISPLAY2
MultiMonitorTool.exe /SetNextPrimary            :: rotate primary through all panels
```

### Resolution / orientation / scaling

```bat
MultiMonitorTool.exe /setmax \\.\DISPLAY2 \\.\DISPLAY3       :: max supported res
MultiMonitorTool.exe /SetOrientation 2 270                  :: 0|90|180|270
MultiMonitorTool.exe /SetScale "\\.\DISPLAY1" 125           :: absolute %
MultiMonitorTool.exe /SetScale "Primary" 0                  :: 0 = recommended
MultiMonitorTool.exe /SetScale "\\.\DISPLAY2" -1            :: one step below recommended
```

### Set everything at once (`/SetMonitors`)

The Swiss-army command. Include only the variables you care about:

```bat
:: Full spec
MultiMonitorTool.exe /SetMonitors ^
  "Name=\\.\DISPLAY1 Primary=1 BitsPerPixel=32 Width=1920 Height=1080 DisplayFlags=0 DisplayFrequency=60 DisplayOrientation=0 PositionX=0 PositionY=0"

:: Positions only
MultiMonitorTool.exe /SetMonitors "Name=\\.\DISPLAY1 PositionX=0 PositionY=0" "Name=\\.\DISPLAY2 PositionX=1920 PositionY=0"

:: One setting on one monitor (matched by serial)
MultiMonitorTool.exe /SetMonitors "Name=334DFRGV451 Width=1920 Height=1080"
```

| Variable | Meaning |
|---|---|
| `Name` | Monitor name, ID, or serial |
| `Primary` | `1` = make primary |
| `BitsPerPixel` | Color depth (usually `32`) |
| `Width` / `Height` | Resolution |
| `DisplayFrequency` | Refresh rate (Hz) |
| `DisplayOrientation` | `0`/`1`/`2`/`3` = 0/90/180/270° |
| `PositionX` / `PositionY` | Top-left coordinate on the virtual desktop |

### Save / load layout

```bat
MultiMonitorTool.exe /SaveConfig "C:\Tools\MMT\work.cfg"
MultiMonitorTool.exe /LoadConfig "C:\Tools\MMT\work.cfg"
```

### Power control (DDC/CI hardware only)

```bat
MultiMonitorTool.exe /TurnOff 1
MultiMonitorTool.exe /TurnOn 3 2
MultiMonitorTool.exe /SwitchOffOn \\.\DISPLAY2 \\.\DISPLAY3
```

### Move windows

```bat
MultiMonitorTool.exe /MoveWindow Primary All                      :: everything → primary
MultiMonitorTool.exe /MoveWindow Primary Process "iexplore.exe"
MultiMonitorTool.exe /MoveWindow Next Process "firefox.exe"
MultiMonitorTool.exe /MoveWindow 2 Title "Hello World"
MultiMonitorTool.exe /MoveWindow 3 Class "CabinetWClass"          :: Explorer windows
MultiMonitorTool.exe /MoveWindow 2 All 3                          :: from monitor 3 → 2

:: combine with placement
MultiMonitorTool.exe /MoveWindow Next Process "firefox.exe" /WindowLeft 10 /WindowTop 10
MultiMonitorTool.exe /MoveWindow Next Process "firefox.exe" /WindowWidth 600 /WindowHeight 400
```

### Preview & export

```bat
MultiMonitorTool.exe /PreviewOnly \\.\DISPLAY1 10 10 300 200      :: x y width height optional
MultiMonitorTool.exe /scomma "monitors.csv"                      :: also /stext /stab /shtml /sxml
```

---

## 7. Recipes

### 🔁 Restore my layout every login

Task Scheduler → **Create Task** → Trigger *At log on* → Action:
```bat
MultiMonitorTool.exe /LoadConfig "C:\Tools\MMT\layout.cfg"
```

### 🎮 "Gaming mode" — single monitor on demand

`gaming-on.bat`:
```bat
@echo off
MultiMonitorTool.exe /SaveConfig "C:\Tools\MMT\before-gaming.cfg"
MultiMonitorTool.exe /disable \\.\DISPLAY2 \\.\DISPLAY3
MultiMonitorTool.exe /SetPrimary \\.\DISPLAY1
```

`gaming-off.bat`:
```bat
@echo off
MultiMonitorTool.exe /LoadConfig "C:\Tools\MMT\before-gaming.cfg"
```

### 🧹 Corral runaway apps

```bat
MultiMonitorTool.exe /MoveWindow 2 Class "CabinetWClass"     :: all Explorer windows → monitor 2
MultiMonitorTool.exe /MoveWindow Primary All                 :: panic button: collect everything
```

### 🌙 Audit your setup to a file

```bat
MultiMonitorTool.exe /shtml "C:\Tools\MMT\report.html"
```

---

## 8. Windows 11 24H2 Gotchas

> ⚠️ The 24H2 update broke several display APIs. v2.15+ includes workarounds for *Set as primary*, *Load config*, `/SetMonitors`, `/SetPrimary`, and `/LoadConfig`.

- If **every** action fails outright: open Windows **Settings → Display**, change *anything* (or unplug/replug a monitor), then return to MultiMonitorTool and retry.
- v2.15+ re-applies configs **5×** by default for reliability on complex setups. Tune via `MonitorsConfigNumOfCalls` in `MultiMonitorTool.cfg`.
- Disabled-monitor geometry is now read straight from the Registry — more reliable for enabling panels back.

---

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| Monitor reappears in the *wrong* position after enable | Use `/EnableAtPosition`, or save & `/LoadConfig` instead of `/enable` |
| Layout doesn't match physical monitors on load | Enable **Use Monitor ID In Load Config** and/or **Use Serial Number In Load Config** |
| A monitor is missing from the list | **Options → Show Duplicate Monitors** (and *Show Disconnected Monitors*) |
| Same monitor listed twice | Toggle **Show Duplicate Monitors** off |
| Blank Monitor ID / serial fields | Info isn't exposed by that panel/GPU; fall back to `\\.\DISPLAYn` |
| Commands silently do nothing on 24H2 | Jiggle a setting in Windows Display, then retry (see [§8](#8-windows-11-24h2-gotchas)) |
| `/TurnOff` / `/TurnOn` ignored | Hardware lacks **DDC/CI** support — no software fix |
| `.cfg` not saved from a batch file | Specify the **full path** to the config file |

---

## 10. Appendix

### Useful persistent options (`MultiMonitorTool.cfg` / GUI Options)

- **Use Monitor ID In Load Config** — match by hardware ID *(default ON)*
- **Use Serial Number In Load Config** — match by physical serial
- **Sort On Every Update** — keep lists ordered as monitors change
- **Always On Top** — for the main and preview windows
- **MonitorsConfigNumOfCalls** — retry count for applying configs (default `5`)

### Tray / hidden operation

```bat
MultiMonitorTool.exe /TrayIcon 1 /StartAsHidden 1
```

### Where to address monitors by hardware (copy-paste finder)

1. Launch the GUI → `Ctrl+A` to select all monitors.
2. **Options → Copy /SetMonitors Command Mode → Use Serial Number as Name**.
3. **Edit → Copy /SetMonitors Command** → paste into your script.

### License & source

Freeware by Nir Sofer (NirSoft). Portable single executable, 32-bit and x64 builds, translatable via `/savelangfile`. Free to redistribute unmodified and non-commercially.

---

*Reference: MultiMonitorTool v2.21 official documentation. Verify command syntax against your installed version with `MultiMonitorTool.exe /?` or the bundled help.*
