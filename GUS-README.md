# GUS — Grand Unified Script

**One command. Fixes PowerShell for everyone.**

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
| `is not digitally signed` from OneDrive-synced files | `GUS-Run.cmd` launcher strips MOTW + bypasses policy |
| GPO enforces AllSigned at MachinePolicy or UserPolicy scope | Stub loads the template via `[scriptblock]::Create()` from raw content — no script-file policy check |
| TLS 1.2/1.3 negotiation failures against PSGallery | Additive enable (preserves Tls13) |
| `NuGet provider is required` prompt every install | Installs NuGet provider |
| `Untrusted repository` prompt on every install | Trusts PSGallery |
| Slow, outdated PowerShellGet | Installs Microsoft.PowerShell.PSResourceGet |
| PSReadLine 2.0.0 from 2017 still in use on Win PS 5.1 | Installs latest, imports it explicitly |
| No predictive autocomplete | Enables PSReadLine + CompletionPredictor (PS 7+) |
| `Out-File` defaults to UTF-16 LE on PS 5.1, breaking CI | UTF-8 everywhere via `$PSDefaultParameterValues` |
| Native commands (openssl, ipconfig) produce mojibake | `chcp 65001` for the session (only if not already 65001) |
| `Invoke-WebRequest` is 50x slower than it should be | `$ProgressPreference = SilentlyContinue` |
| `Up Arrow` walks all history, not prefix-filtered | Rebinds to `HistorySearchBackward` |
| `Tab` shows one completion at a time | Rebinds to `MenuComplete` |
| Passwords end up in history | History filter for secret-shaped strings (password/token/bearer/40+ char tokens) |
| `cd C:\very\deeply\nested\...` -> PathTooLong | Enables LongPathsEnabled (admin) |
| Each new admin workstation needs a 2-hour setup | One double-click |
| Profile in PS 5.1 != profile in PS 7 | Single shared template, stub loaders in both |
| `gh completion -s powershell` shells out every shell start (~500ms each for gh/kubectl/docker) | Cached to `~/.gus/completions/<tool>.ps1`, auto-invalidated when tool binary newer than cache |
| Defender real-time scan locks freshly written `.ps1` | `Set-ContentWithRetry` with exponential backoff |
| OneDrive-redirected Documents folder adds 3-5 seconds to every shell startup | `-RelocateModules` moves modules to `%LOCALAPPDATA%\PowerShell\Modules` |
| Tab-completion for winget / dotnet / az / kubectl / gh / docker | Auto-registered when each tool is present |
| `sudo` muscle memory | `sudo` function (uses real `gsudo` if installed) |
| `touch`, `which`, `mkcd`, `..`, `...` | Defined |
| Forgotten where the profile file lives | `edit-profile`, `reload-profile`, `gus-status`, `gus-perf` |

Optional, off by default:

- **Oh My Posh** — modern prompt themes, installed via `winget` (the module version is deprecated).
- **Nerd Fonts** — CaskaydiaCove NF, installed via `oh-my-posh font install`.

---

## Files

| File | Purpose |
|---|---|
| `GUS-Run.cmd` | **Canonical launcher.** Double-click to install. Strips MOTW and runs with `-NoProfile -ExecutionPolicy Bypass`. Forwards any arguments to the orchestrator. |
| `GUS-Invoke.ps1` | Orchestrator. Can be invoked directly if you don't need the MOTW/policy bypass. |
| `GUS.Profile.ps1` | Profile template. Gets copied to `~\.gus\` and loaded as a scriptblock by stubs in both PS 5.1 and PS 7 profile locations. |
| `GUS-README.md` | This file. |

All four files must live in the **same folder**. `GUS-Run.cmd` and `GUS-Invoke.ps1` both look for siblings via `%~dp0` / `$PSScriptRoot`. Put them somewhere durable (e.g. `C:\Tools\GUS\`) before running. If you keep them in a OneDrive-synced repo, use `GUS-Run.cmd` exclusively — it's built for that case.

---

## Quick start

```
# 1. Drop all four GUS files into a folder.
# 2. Double-click GUS-Run.cmd.
```

That's it. The launcher handles:

- Mark of the Web (OneDrive, downloads, network shares)
- Execution policy (process-scope Bypass, no persistent change)
- Spaces in paths
- The "press any key to close" courtesy when double-clicked from Explorer

If you prefer PowerShell-native invocation:

```powershell
cd C:\Tools\GUS
.\GUS-Run.cmd                   # equivalent to double-click
.\GUS-Run.cmd -IncludeOhMyPosh  # forwards args to the orchestrator
```

Once installed, **open a new PowerShell window** and verify:

```powershell
gus-status
```

You should see a `GUS loaded in NNNms` banner at shell startup. If `NNN` is over ~1500ms, see [Performance](#performance).

---

## Operation modes

`GUS-Invoke.ps1` is parameter-set driven. Pick exactly one mode flag (or none, for default install). All modes accept `-WhatIf` to preview.

### Install — default

```
GUS-Run.cmd                       # Current user, full setup
GUS-Run.cmd -Scope AllUsers       # Machine-wide (requires elevation)
GUS-Run.cmd -IncludeOhMyPosh      # Add the pretty prompt (uses winget)
GUS-Run.cmd -IncludeOhMyPosh -IncludeNerdFonts   # Full glamour
GUS-Run.cmd -Minimal              # Locked-down env: no module installs
```

Runs the full setup: environment hygiene, module installs, profile generation, both edition stubs.

`-Minimal` is for environments where you can't install modules (WDAC, AppLocker, air-gapped). It still sets execution policy, TLS, encoding defaults, and writes the profile — the parts that work entirely with what ships in the box.

### Diagnose — read-only

```
GUS-Run.cmd -Diagnose
```

Prints a health check: execution policy across all scopes, TLS state, NuGet provider version, PSGallery trust, installed module versions and conflict detection, profile presence in all four `$PROFILE` slots, GUS template presence, LongPathsEnabled state, console encoding, PSReadLine config. Makes zero changes.

### Repair — when something's wedged

```
GUS-Run.cmd -Repair
```

Common failure mode: PSReadLine ends up installed in two locations (CurrentUser + AllUsers), or PowerShellGet got confused by an interrupted install. Repair removes duplicates from non-`$PSHOME` locations and force-reinstalls. Leaves the `$PSHOME` copy of PSReadLine in place — it's the baseline; we shadow it, never remove it.

### Update — just bump modules

```
GUS-Run.cmd -Update
```

Updates PSReadLine, PSResourceGet, CompletionPredictor, Terminal-Icons, posh-git, and oh-my-posh (if installed) to latest. Skips environment setup. Use weekly/monthly.

### Restore — revert

```
GUS-Run.cmd -Restore
```

Restores the most recent profile stub backups from `~\.gus\backups\`. Doesn't touch installed modules — those are non-destructive.

### Uninstall — remove GUS, keep the rest

```
GUS-Run.cmd -Uninstall
```

Removes the profile stubs and the shared template. Leaves modules, execution policy, TLS settings, NuGet, and `LongPathsEnabled` in place because plenty of other things use them. Backups are retained in `~\.gus\backups\`.

### RelocateModules — fix OneDrive module-load slowness

```
GUS-Run.cmd -RelocateModules
```

Finds every entry in `$env:PSModulePath` matching `OneDrive`, moves all module subdirectories from those locations into `%LOCALAPPDATA%\PowerShell\Modules` (a local, non-synced path both editions can share), and prepends that path to the user-scope `PSModulePath`. **Typically cuts cold profile load by 3-5 seconds** on machines where Documents is OneDrive-redirected. See [Performance](#performance).

---

## What gets written where

CurrentUser scope (default):

| Path | What |
|---|---|
| `~\.gus\GUS.Profile.ps1` | The actual profile content (single source of truth) |
| `~\.gus\completions\<tool>.ps1` | Cached `gh` / `kubectl` / `docker` completion scripts. Regenerated when the tool's binary is newer than the cache. |
| `~\.gus\backups\*.bak` | Backups of anything overwritten, timestamped |
| `~\Documents\WindowsPowerShell\profile.ps1` | Stub for Windows PowerShell 5.1: loads the template via scriptblock |
| `~\Documents\PowerShell\profile.ps1` | Stub for PowerShell 7: same |
| `%LOCALAPPDATA%\PowerShell\Modules\*` | (After `-RelocateModules`) modules relocated off OneDrive |
| `HKCU\Environment\PSModulePath` | (After `-RelocateModules`) prepended with the LOCALAPPDATA path |

With `-Scope AllUsers`:

| Path | What |
|---|---|
| `%WINDIR%\System32\WindowsPowerShell\v1.0\profile.ps1` | Stub for Win PS 5.1 all users |
| `%ProgramFiles%\PowerShell\7\profile.ps1` | Stub for PS 7 all users |
| `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled` | DWORD = 1 |

The stub itself is small and uses scriptblock loading:

```powershell
$gusProfile = "C:\Users\you\.gus\GUS.Profile.ps1"
if (Test-Path $gusProfile) {
    try {
        . ([scriptblock]::Create((Get-Content -LiteralPath $gusProfile -Raw)))
    } catch {
        Write-Warning "GUS profile load failed: $($_.Exception.Message)"
    }
}
```

`Get-Content` reads bytes (no policy check). `[scriptblock]::Create()` builds executable code from a string (no policy check). The `.` dot-sources the scriptblock in current scope. At no point does PowerShell evaluate "is this script file signed?" — because there's no script file being executed.

Edit the shared template (`~\.gus\GUS.Profile.ps1`) — your changes load in both editions. Or use the helper:

```powershell
edit-profile     # opens the template in code/notepad++/notepad
reload-profile   # re-sources without restarting the shell
gus-status       # what's loaded right now, plus profile load time
gus-perf         # section-by-section profile load timing
```

---

## What it deliberately doesn't do

- **Doesn't set `$ErrorActionPreference = 'Stop'`** globally. That makes interactive use miserable (every typo terminates). Set it per-script with `[CmdletBinding()]` instead.
- **Doesn't disable Defender / SmartScreen / firewall / anything security-related.**
- **Doesn't auto-install modules in `-Minimal` mode.** Respects locked-down environments.
- **Doesn't use third-party "tweaker" tools.** Every change is a Microsoft-documented setting, registry key, or PSGallery module.
- **Doesn't touch `$PSEdition` or any other read-only automatic variable.** Reads `$PSVersionTable` instead.
- **Doesn't replace TLS protocols destructively.** It ORs Tls12/Tls13 in, never overwrites — so it doesn't strip Tls13 from systems that had it.
- **Doesn't remove OneDrive paths from `PSModulePath` during `-RelocateModules`.** PowerShell automatically re-adds the personal Documents path at startup based on Known Folder location. The script can't suppress that. It just makes sure those folders are empty so the discovery scan is fast.
- **Doesn't sign anything.** If your enterprise requires signed scripts, sign the GUS files yourself with a code-signing cert and import to Trusted Publishers (see [Troubleshooting](#troubleshooting)).

---

## Compatibility

| Environment | Status |
|---|---|
| Windows PowerShell 5.1 | Full support |
| PowerShell 7.4 LTS (until Nov 2026) | Full support |
| PowerShell 7.5 STS | Full support |
| PowerShell 7.6 LTS (current) | Full support |
| Windows PowerShell ISE | Profile loads, PSReadLine features skipped (ISE doesn't load PSReadLine), prompt customization skipped |
| VS Code integrated terminal | Full support, banner suppressed |
| Windows Terminal | Full support |
| ConEmu / other terminals | Full support |
| OneDrive-redirected Documents | Full support, but `-RelocateModules` recommended for performance |
| GPO enforcing AllSigned | Full support via scriptblock loader in stubs |
| WDAC / AppLocker | Use `-Minimal` mode |
| PowerShell on Linux/macOS | Untested; most features should work, registry/wbadmin/winget calls won't |

---

## Performance

Cold profile load target: **under 1500ms.**

If `gus-status` shows a profile load time over that, run `gus-perf` to see section-by-section timing. Anything over 500ms in a single section is colored red.

Common patterns:

- **`OPTIONAL MODULES` section over 1000ms** — Terminal-Icons / posh-git loading slowly. Almost always because they're stored under a OneDrive-synced PSModulePath. Run `GUS-Run.cmd -RelocateModules`.
- **`ARGUMENT COMPLETERS` section over 1000ms** — cached completion scripts haven't been generated yet. First run after install builds the cache; subsequent loads are fast. Force-rebuild with `gus-refresh-completions`.
- **Welcome banner shows `GUS loaded in Xms` but PowerShell reports a much higher total** — the gap is in PowerShell's startup module discovery, which happens before the profile runs. This is dominated by `PSModulePath` entries through OneDrive's Files-On-Demand filter. `-RelocateModules` is again the fix.

To verify whether modules are routed through OneDrive:

```powershell
$env:PSModulePath -split ';' | ForEach-Object {
    $count = if (Test-Path $_) {
        (Get-ChildItem $_ -ErrorAction SilentlyContinue | Measure-Object).Count
    } else { 0 }
    "{0,5} entries  {1}" -f $count, $_
}
```

If any large entry contains `OneDrive`, that's the bottleneck.

---

## Footguns explicitly addressed

A list of "well, *technically*..." mistakes that real PowerShell setup scripts make. GUS doesn't.

1. **`$PSEdition = 'Core'`** — read-only automatic variable. Assigning to it throws. GUS reads `$PSVersionTable.PSVersion.Major -ge 7` instead.
2. **`[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`** — assignment, not OR. Strips Tls13 from sessions that had it. GUS uses `-bor`.
3. **`$ErrorActionPreference = 'Stop'` in profile** — makes interactive use unusable. GUS sets it only inside the bootstrap script's own scope, never in the profile.
4. **`Install-Module -Force` without `-AllowClobber`** — fails when reinstalling PSReadLine because the in-box copy exports the same command names.
5. **`Set-PSReadLineOption -PredictionSource HistoryAndPlugin` on PS 5.1** — PS 5.1 has no plugin model. GUS uses `History` on 5.1, `HistoryAndPlugin` on 7+.
6. **Hardcoded `-Scope CurrentUser` when `-Scope AllUsers` was passed at top level** — silent bug, real install ends up in wrong place. GUS threads `$Scope` everywhere.
7. **Unicode characters (em-dash, box-drawing) in `.ps1` files without ensuring BOM-UTF-8** — renders as parser errors on PS 5.1 if the file is saved BOM-less. GUS is pure ASCII.
8. **Writing the profile to `$PROFILE` (which is host-specific)** — the profile only loads in console. GUS writes to `$PROFILE.CurrentUserAllHosts` so VS Code / Terminal / console all get it.
9. **Writing only one profile path, ignoring PS 5.1 vs PS 7 split** — settings work in one edition only. GUS writes stubs to both.
10. **Forgetting that `$PROFILE.CurrentUserAllHosts` is `profile.ps1`, not `Microsoft.PowerShell_profile.ps1`** — different file, different load order. GUS uses AllHosts deliberately.
11. **Replacing the user's existing profile without backup** — irreversible. GUS backs up to `~\.gus\backups\<name>.<edition>.<timestamp>.bak` every time.
12. **Profile that fails fatally on a missing module** — kills every new shell launch until you fix it. GUS uses `Get-Module -ListAvailable` guards everywhere.
13. **Setting prompt to use ANSI escapes without checking the host supports them** — corrupted prompt in ISE / Pinvoke contexts. GUS skips its prompt entirely in ISE.
14. **Multi-line cast expressions** — `([Type1][Type2]::Method())` split across lines fails to parse on PS 5.1, even inside parens. GUS uses `New-Object` form.
15. **`$GitPromptScriptBlock` to get posh-git status** — that's posh-git's entire prompt function, including Write-Host side effects. Calling it from a custom prompt produces a doubled prompt. GUS uses `Get-GitStatus` and renders the branch portion manually.
16. **Plain `. $profile` in the stub** — fails when GPO enforces AllSigned or when MOTW propagates. GUS uses `. ([scriptblock]::Create((Get-Content -Raw)))`.
17. **`Set-Content` on `.ps1` immediately after a previous write** — Defender real-time scan can lock the file for 100-1500ms. GUS retries with exponential backoff.
18. **`gh completion -s powershell | iex` in the profile** — generates kilobytes of completion script via child process every shell start. GUS caches to disk, regenerates only when the tool binary is newer.
19. **Modules in OneDrive-redirected Documents folder** — every import goes through the OneDrive filter driver, adding 3-5 seconds to cold profile load. GUS `-RelocateModules` moves them locally.

---

## Troubleshooting

### "is not digitally signed. You cannot run this script"

Two causes:

1. **MOTW (Mark of the Web)** on the file because it was downloaded or synced from OneDrive. Combined with `RemoteSigned` execution policy, this requires a signature on files marked as "from the internet."
2. **GPO enforces `AllSigned`** at `MachinePolicy` or `UserPolicy` scope. Process-scope `-ExecutionPolicy Bypass` can't override these.

**Fix:** use `GUS-Run.cmd` instead of `.\GUS-Invoke.ps1` directly. It strips MOTW via `Unblock-File` and launches with process-scope Bypass. The stubs use scriptblock loading so the GPO scope doesn't apply at runtime.

To diagnose:

```powershell
Get-ExecutionPolicy -List
Get-Item .\GUS-Invoke.ps1 -Stream Zone.Identifier -ErrorAction SilentlyContinue
```

### "I ran it, but my new shell looks the same."

You're probably still in the *old* shell. The profile loads at PowerShell startup, not during the run. Open a fresh terminal/tab.

If still nothing:

```
GUS-Run.cmd -Diagnose
```

Look for the "Profiles" section — every entry should show `(present)`. If absent, GUS couldn't write them. Check `Documents\PowerShell\` and `Documents\WindowsPowerShell\` permissions.

### "Boxes/glyphs show as `??` after `-IncludeOhMyPosh`"

You need a Nerd Font. Run with `-IncludeNerdFonts` (or `oh-my-posh font install` manually), then set Windows Terminal's font to `CaskaydiaCove NF`:

1. Open Windows Terminal Settings (Ctrl+,)
2. Pick the PowerShell profile
3. Appearance → Font face → CaskaydiaCove Nerd Font

### "Multiple versions of PSReadLine found"

Run `GUS-Run.cmd -Repair`. This is the most common "wedged module" case.

### "Profile takes 5+ seconds to load"

If your Documents folder is OneDrive-redirected (path like `~\OneDrive - YourOrg\Documents\WindowsPowerShell\Modules`), every module load goes through the OneDrive filter driver. Fix:

```
GUS-Run.cmd -RelocateModules
```

Then open a new shell. Cold load should drop by 3-5 seconds. Run `gus-perf` to see the section-by-section breakdown.

If oh-my-posh is the culprit, switch to a lighter theme (`oh-my-posh init pwsh --config minimal`). If posh-git is, set `$GitPromptSettings.EnableFileStatus = $false`.

### "FATAL: The process cannot access the file ... because it is being used by another process"

Three causes, in order of likelihood:

1. **Defender real-time protection** scanning the file after a recent write. GUS retries with backoff; if all 6 retries fail, close any open PowerShell windows and re-run.
2. **Another PowerShell window** has the template open (e.g. via `edit-profile`, `gus-perf`, or just sitting at a prompt with the profile loaded).
3. **An editor** (VS Code, Notepad++) has the file open. Save and close.

The fatal-error handler lists other running PowerShell processes by PID to help you find the culprit.

### "I broke the profile and PowerShell won't start cleanly"

Open PowerShell bypassing the profile:

```cmd
powershell.exe -NoProfile
```

then:

```powershell
.\GUS-Invoke.ps1 -Restore
```

### "I want the profile to do something extra"

Edit `~\.gus\GUS.Profile.ps1` (`edit-profile` opens it). Your additions survive `-Update` but get overwritten by `-Repair` or `-Install`. The clean pattern: put your additions in a sibling file like `~\.gus\Custom.ps1` and add this to the bottom of `GUS.Profile.ps1`:

```powershell
$custom = Join-Path (Split-Path $PSCommandPath) 'Custom.ps1'
if (Test-Path $custom) { . $custom }
```

`-Update` and `-Repair` won't clobber your customizations because they only rewrite `GUS.Profile.ps1`, not sibling files.

### "I want to sign GUS so my enterprise GPO accepts it natively"

```powershell
# One-time: make a self-signed code-signing cert
$cert = New-SelfSignedCertificate `
    -Subject "CN=$env:USERNAME PowerShell Signing" `
    -Type CodeSigningCert `
    -CertStoreLocation Cert:\CurrentUser\My `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(5)

# Trust on this machine
foreach ($store in 'Root','TrustedPublisher') {
    $s = New-Object System.Security.Cryptography.X509Certificates.X509Store($store,'CurrentUser')
    $s.Open('ReadWrite'); $s.Add($cert); $s.Close()
}

# Sign the GUS files
Get-ChildItem .\GUS*.ps1 | ForEach-Object {
    Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert
}
```

For a fleet, export the cert as `.cer`, push to Trusted Publisher + Trusted Root via Intune device configuration, then sign GUS centrally.

---

## Design choices, briefly

- **Single shared template, stub loaders, scriptblock loading.** PS 5.1 and PS 7 have different `$PROFILE` paths. Rather than maintain two copies, GUS puts the real profile in `~\.gus\GUS.Profile.ps1` and writes two tiny stubs that load the template via `[scriptblock]::Create((Get-Content -Raw))`. Edits propagate to both editions. The scriptblock indirection makes the loader immune to execution policy and MOTW.
- **`.cmd` launcher as canonical entry point.** When GUS lives in an OneDrive-synced repo (or anywhere downloads land), `.\GUS-Invoke.ps1` will hit MOTW + execution policy gates on first run. `GUS-Run.cmd` handles both transparently.
- **ASCII output and source only.** No em-dashes, no box-drawing, no smart quotes anywhere in the `.ps1` files. PS 5.1 reads `.ps1` as system ANSI codepage unless there's a UTF-8 BOM; non-ASCII content without a BOM corrupts parsing.
- **Parameter sets, not boolean spaghetti.** Mutually exclusive modes (Install/Diagnose/Repair/Update/Restore/Uninstall/RelocateModules) are real parameter sets so you can't combine `-Diagnose -Repair` and end up in an undefined state.
- **PSResourceGet preferred, PowerShellGet fallback.** PSResourceGet is roughly twice as fast and avoids the PackageManagement provider model. GUS tries it first, falls back gracefully.
- **No global `$ErrorActionPreference = 'Stop'`.** Set per-script via `[CmdletBinding()]` instead. The bootstrap itself doesn't set it either; each operation handles its own errors and reports continue/skip/fail.
- **Retry on transient IO locks.** `Set-Content` against `.ps1` files often races with Defender scans. GUS retries 6 times with exponential backoff (250-1500ms) before failing fatally.
- **Idempotent.** Every step checks current state and reports `[--]` (skip) if already done. Re-running is harmless.

---

## License & attribution

Public domain / do whatever. Built on the shoulders of: PSReadLine team (Jason Helmick et al.), PSResourceGet team, Jan De Dobbeleer (Oh My Posh), the Terminal-Icons and posh-git maintainers, the PowerShell Team's design docs and release notes.
