# GUS — Grand Unified Script

**One script. Fixes PowerShell for everyone.**

GUS bootstraps a sane PowerShell environment in a single command. It targets both Windows PowerShell 5.1 (the one Microsoft still ships with Windows) and PowerShell 7+ (the modern cross-platform one). It's idempotent, reversible, and CI-friendly.

GUS is for two audiences:

- **The neophyte** who installed PowerShell 7 or opened the default Windows PowerShell prompt, hit five papercuts in the first ten minutes, and wants to know how to make it stop.
- **The advanced user** who's tired of writing the same fix script for every new machine, every new tenant, every fresh image.

---

## What "fixed" means

Out of the box, PowerShell has a long list of foot-guns that bite both audiences. GUS fixes each one with a documented, reversible change.

| Pain point | What GUS does |
|---|---|
| Scripts blocked by `Set-ExecutionPolicy` errors | Sets CurrentUser RemoteSigned |
| TLS 1.2/1.3 negotiation failures against PSGallery | Additive enable (preserves Tls13) |
| `NuGet provider is required` prompt every install | Installs NuGet provider |
| `Untrusted repository` prompt on every install | Trusts PSGallery |
| Slow, outdated PowerShellGet | Installs Microsoft.PowerShell.PSResourceGet |
| PSReadLine 2.0.0 from 2017 still in use on Win PS 5.1 | Installs latest, imports it explicitly |
| No predictive autocomplete | Enables PSReadLine + CompletionPredictor |
| `Out-File` defaults to UTF-16 LE on PS 5.1, breaking CI | UTF-8 everywhere via `$PSDefaultParameterValues` |
| Native commands (openssl, ipconfig) produce mojibake | `chcp 65001` for the session |
| `Invoke-WebRequest` is 50× slower than it should be | `$ProgressPreference = SilentlyContinue` |
| `Up Arrow` walks all history, not prefix-filtered | Rebinds to `HistorySearchBackward` |
| `Tab` shows one completion at a time | Rebinds to `MenuComplete` |
| Passwords end up in history | History filter for secret-shaped strings |
| `cd C:\very\deeply\nested\...` → PathTooLong | Enables LongPathsEnabled (admin) |
| Each new admin workstation needs a 2-hour setup | One command |
| Profile in PS 5.1 ≠ profile in PS 7 | Single shared template, stub loaders in both |
| `Up Arrow` shows you nothing useful | History prediction with ListView |
| Tab-completion for winget / dotnet / az / kubectl / gh / docker | Auto-registered when each tool is present |
| `sudo` muscle memory | `sudo` function (uses real `gsudo` if installed) |
| `touch`, `which`, `mkcd`, `..`, `...` | Defined |
| Forgotten where the profile file lives | `edit-profile`, `reload-profile`, `gus-status` |

Optional, off by default:

- **Oh My Posh** — modern prompt themes, installed via `winget` (the module version is deprecated).
- **Nerd Fonts** — CaskaydiaCove NF, installed via `oh-my-posh font install`.

---

## Files

| File | Purpose |
|---|---|
| `Invoke-GUS.ps1` | Orchestrator. Run this. |
| `GUS.Profile.ps1` | Profile template. Gets copied to `~\.gus\` and sourced by stubs in both PS 5.1 and PS 7 profile locations. |
| `README.md` | This file. |

`Invoke-GUS.ps1` expects `GUS.Profile.ps1` to live in the **same folder**. Put them both somewhere durable (e.g. `C:\Tools\GUS\`) before running, especially if you plan to re-run for updates.

---

## Quick start

```powershell
# 1. Drop both files into a folder, cd there:
cd C:\Tools\GUS

# 2. If you've never run a script on this machine:
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force

# 3. Run it:
.\Invoke-GUS.ps1

# 4. Open a NEW PowerShell window. Try:
gus-status
```

That's it. Re-run any time to update or repair.

---

## Operation modes

`Invoke-GUS.ps1` is parameter-set driven. Pick exactly one mode flag (or none, for default install).

### Install — default

```powershell
.\Invoke-GUS.ps1                    # Current user
.\Invoke-GUS.ps1 -Scope AllUsers    # Machine-wide (requires elevation)
.\Invoke-GUS.ps1 -IncludeOhMyPosh   # Add the pretty prompt (uses winget)
.\Invoke-GUS.ps1 -IncludeOhMyPosh -IncludeNerdFonts   # Full glamour
.\Invoke-GUS.ps1 -Minimal           # Locked-down env: no module installs
```

Runs the full setup: environment hygiene, module installs, profile generation.

`-Minimal` is for environments where you can't install modules (WDAC, AppLocker, air-gapped). It still sets execution policy, TLS, encoding defaults, and writes the profile — the parts that work entirely with what ships in the box.

### Diagnose — read-only

```powershell
.\Invoke-GUS.ps1 -Diagnose
```

Prints a health check. Makes zero changes. Useful before/after, and when someone asks you "why doesn't this script work on my box."

### Repair — when something's wedged

```powershell
.\Invoke-GUS.ps1 -Repair
```

Common failure mode: PSReadLine ends up installed in two locations (CurrentUser + AllUsers), or PowerShellGet got confused by an interrupted install. Repair removes duplicates, force-reinstalls, and trusts PSGallery again. Leaves the `$PSHOME` copy of PSReadLine in place (it's the baseline; we shadow it, never remove it).

### Update — just bump modules

```powershell
.\Invoke-GUS.ps1 -Update
```

Updates PSReadLine, PSResourceGet, CompletionPredictor, Terminal-Icons, posh-git, and oh-my-posh (if installed) to latest. Skips environment setup. Use weekly/monthly.

### Restore — revert

```powershell
.\Invoke-GUS.ps1 -Restore
```

Restores the most recent profile stub backups from `~\.gus\backups\`. Doesn't touch installed modules — those are non-destructive.

### Uninstall — remove GUS, keep the rest

```powershell
.\Invoke-GUS.ps1 -Uninstall
```

Removes the profile stubs and the shared template. Leaves modules, execution policy, TLS settings, and NuGet in place because plenty of other things use them.

---

## What gets written where

| Path | What |
|---|---|
| `~\.gus\GUS.Profile.ps1` | The actual profile content (single source of truth) |
| `~\.gus\backups\*.bak` | Backups of anything we overwrote, timestamped |
| `~\Documents\WindowsPowerShell\profile.ps1` | Stub: `. ~\.gus\GUS.Profile.ps1` (for Windows PowerShell 5.1) |
| `~\Documents\PowerShell\profile.ps1` | Stub: `. ~\.gus\GUS.Profile.ps1` (for PowerShell 7) |

With `-Scope AllUsers`:

| Path | What |
|---|---|
| `%WINDIR%\System32\WindowsPowerShell\v1.0\profile.ps1` | Stub for Win PS 5.1 all users |
| `%ProgramFiles%\PowerShell\7\profile.ps1` | Stub for PS 7 all users |
| `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled` | DWORD = 1 |

Edit the shared template (`~\.gus\GUS.Profile.ps1`) — your changes load in both editions. Or use the helper:

```powershell
edit-profile     # opens the template in code/notepad++/notepad
reload-profile   # re-sources without restarting the shell
```

---

## What it deliberately doesn't do

- **Doesn't set `$ErrorActionPreference = 'Stop'`** globally. That makes interactive use miserable (every typo terminates). Set it per-script with `[CmdletBinding()]` instead.
- **Doesn't disable Defender/SmartScreen/firewall/anything security-related.**
- **Doesn't auto-install modules in `-Minimal` mode.** Respects locked-down environments.
- **Doesn't use third-party "tweaker" tools.** Every change is a Microsoft-documented setting, registry key, or PSGallery module.
- **Doesn't touch `$PSEdition` or any other read-only automatic variable.** Reads `$PSVersionTable` instead. (Yes, this is a footgun even seasoned PowerShell people hit.)
- **Doesn't replace TLS protocols destructively.** It ORs Tls12/Tls13 in, never overwrites — so it doesn't strip Tls13 from systems that had it.

---

## Compatibility

| Environment | Status |
|---|---|
| Windows PowerShell 5.1 | Full support |
| PowerShell 7.4 LTS (until Nov 2026) | Full support |
| PowerShell 7.5 STS | Full support |
| PowerShell 7.6 LTS (current) | Full support |
| Windows PowerShell ISE | Profile loads, PSReadLine features skipped (ISE doesn't load PSReadLine) |
| VS Code integrated terminal | Full support, banner suppressed |
| Windows Terminal | Full support |
| ConEmu / other terminals | Full support |
| PowerShell on Linux/macOS | Untested; most features should work, registry/wbadmin/winget calls won't |

---

## Footguns explicitly addressed

A list of "well, *technically*..." mistakes that real PowerShell setup scripts make. GUS doesn't.

1. **`$PSEdition = 'Core'`** — this is a read-only automatic variable in PowerShell. Assigning to it throws. GUS reads `$PSVersionTable.PSVersion.Major -ge 7` instead.
2. **`[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`** — assignment, not OR. Strips Tls13 from sessions that had it. GUS uses `-bor`.
3. **`$ErrorActionPreference = 'Stop'` in profile** — makes interactive use unusable. GUS sets it only inside the bootstrap script's own scope, never in the profile.
4. **`Install-Module -Force` without `-AllowClobber`** — fails when reinstalling PSReadLine because the in-box copy exports the same command names.
5. **`Set-PSReadLineOption -PredictionSource HistoryAndPlugin` on PS 5.1** — PS 5.1 has no plugin model. GUS uses `History` on 5.1, `HistoryAndPlugin` on 7+.
6. **Hardcoded `-Scope CurrentUser` when `-Scope AllUsers` was passed at top level** — silent bug, real install ends up in wrong place. GUS threads `$Scope` everywhere.
7. **UTF-8 box-drawing characters in the script's banner without ensuring BOM-UTF-8** — banner renders as mojibake on PS 5.1 if the script is re-saved without BOM. GUS uses ASCII-only output.
8. **Writing the profile to `$PROFILE` (which is host-specific)** — the profile only loads in console. GUS writes to `$PROFILE.CurrentUserAllHosts` so VS Code / Terminal / console all get it.
9. **Writing only one profile path, ignoring PS 5.1 vs PS 7 split** — settings work in one edition only. GUS writes stubs to both.
10. **Forgetting that `$PROFILE.CurrentUserAllHosts` is `profile.ps1`, not `Microsoft.PowerShell_profile.ps1`** — different file, different load order. GUS uses AllHosts deliberately.
11. **Replacing the user's existing profile without backup** — irreversible. GUS backs up to `~\.gus\backups\<name>.<timestamp>.bak` every time.
12. **Profile that fails fatally on a missing module** — kills every new shell launch until you fix it. GUS uses `Get-Module -ListAvailable` guards everywhere.
13. **Setting prompt to use ANSI escapes without checking the host supports them** — corrupted prompt in ISE / Pinvoke contexts. GUS skips its prompt entirely in ISE.

---

## Troubleshooting

### "I ran it, but my new shell looks the same."

You're probably still in the *old* shell. The profile loads at PowerShell startup, not during the run. Open a fresh terminal/tab.

If still nothing:
```powershell
.\Invoke-GUS.ps1 -Diagnose
```

Look for the "Profiles" section — every entry should show `(present)`. If they're absent, GUS couldn't write them. Check `Documents\PowerShell\` and `Documents\WindowsPowerShell\` permissions.

### "Boxes/glyphs show as `??` after `-IncludeOhMyPosh`"

You need a Nerd Font. Run with `-IncludeNerdFonts` (or `oh-my-posh font install` manually), then set Windows Terminal's font to `CaskaydiaCove NF`:

1. Open Windows Terminal Settings (Ctrl+,)
2. Pick the PowerShell profile
3. Appearance → Font face → CaskaydiaCove Nerd Font

### "I get `Multiple versions of PSReadLine found`"

Run `.\Invoke-GUS.ps1 -Repair`. This is the most common "wedged module" case.

### "Profile takes forever to load"

Most likely: oh-my-posh init talking to a slow disk, or posh-git scanning a huge repo at prompt time. Measure:

```powershell
Measure-Command { . $PROFILE.CurrentUserAllHosts }
```

If oh-my-posh is the culprit, switch to a lighter theme (`oh-my-posh init pwsh --config minimal`). If posh-git is, set `$GitPromptSettings.EnableFileStatus = $false`.

### "I broke the profile and PowerShell won't start cleanly"

Open PowerShell with `-NoProfile`:
```cmd
powershell.exe -NoProfile
```
then:
```powershell
.\Invoke-GUS.ps1 -Restore
```

### "I want the profile to do something extra"

Edit `~\.gus\GUS.Profile.ps1` (`edit-profile` opens it). Your additions survive `-Update` but get overwritten by `-Repair` or `-Install`. The clean pattern: put your additions in a sibling file like `~\.gus\Custom.ps1` and add this to the bottom of `GUS.Profile.ps1`:
```powershell
$custom = Join-Path (Split-Path $PSCommandPath) 'Custom.ps1'
if (Test-Path $custom) { . $custom }
```
That way `-Update`/`-Repair` won't clobber your customizations.

---

## Design choices, briefly

- **Single shared template, stub loaders.** PS 5.1 and PS 7 have different `$PROFILE` paths. Rather than maintain two copies, GUS puts the real profile in `~\.gus\GUS.Profile.ps1` and writes two tiny stub files that dot-source it. Edits propagate to both editions automatically.
- **ASCII output only.** The previous EXO bootstrap used Unicode box-drawing in its banner and broke when the script file was re-saved BOM-less. GUS uses `==>`, `[OK]`, `[!!]` and friends — encoding-agnostic.
- **Parameter sets, not boolean spaghetti.** Mutually exclusive modes (Install/Diagnose/Repair/Update/Restore/Uninstall) are real parameter sets so you can't combine `-Diagnose -Repair` and end up in an undefined state.
- **PSResourceGet preferred, PowerShellGet fallback.** PSResourceGet is roughly twice as fast and avoids the PackageManagement provider model. GUS tries it first, falls back gracefully.
- **No global `$ErrorActionPreference = 'Stop'`.** Set per-script via `[CmdletBinding()]` instead. The bootstrap itself doesn't set it either; each operation handles its own errors and reports continue/skip/fail.
- **Idempotent.** Every step checks current state and reports `[--]` (skip) if already done. Re-running is harmless.

---

## License & attribution

Public domain / do whatever. Built on the shoulders of: PSReadLine team (Jason Helmick et al.), PSResourceGet team, Jan De Dobbeleer (Oh My Posh), the Terminal-Icons and posh-git maintainers, the PowerShell Team's design docs and release notes.
