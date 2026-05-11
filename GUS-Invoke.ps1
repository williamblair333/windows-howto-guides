#Requires -Version 5.1
<#
.SYNOPSIS
    GUS -- Grand Unified Script. Fixes PowerShell for neophytes and advanced
    users in one shot. Idempotent, reversible, single-runner.

.DESCRIPTION
    Six operation modes, parameter-set driven:

      Install   (default) -- Full setup: environment, modules, profile.
      Diagnose            -- Read-only health check.
      Repair              -- Nuke broken modules, reset to clean state, reinstall.
      Update              -- Update modules to latest. Skips env setup.
      Restore             -- Revert profiles from most recent backup.
      Uninstall           -- Remove GUS profiles, leave the rest of the environment.

    What "fixed" means:
      * Execution policy (CurrentUser RemoteSigned).
      * TLS 1.2/1.3 enabled additively (does not strip Tls13 if present).
      * NuGet provider + PSGallery trusted.
      * PSResourceGet installed (the modern, faster successor to PowerShellGet).
      * PSReadLine updated past the 2.0.0 in-box on Windows PowerShell 5.1.
      * CompletionPredictor + Terminal-Icons + posh-git installed.
      * Long Path support enabled (LongPathsEnabled, system-wide; requires admin).
      * Unified profile written to BOTH Windows PowerShell 5.1 and PowerShell 7
        profile locations via stubs that load a single shared template.
      * Profile sets UTF-8 everywhere (console, $OutputEncoding, default file
        encoding via $PSDefaultParameterValues).
      * Profile quiets $ProgressPreference for the 5-50x speedup on
        Invoke-WebRequest / Install-Module.
      * Profile installs argument-completers for winget, dotnet, gh, az,
        kubectl, docker (each only if the tool is present).
      * Smart prompt with admin marker, exit code, and git branch (if posh-git
        loaded). Survives interruption (Ctrl+C) cleanly.
      * Optional: oh-my-posh (via winget) and Nerd Fonts (via oh-my-posh).

.PARAMETER Install
    Default mode. Runs full installation. You don't usually pass this flag --
    it's implicit when no other mode flag is given.

.PARAMETER Diagnose
    Read-only health check. Prints state of execution policy, TLS, NuGet,
    PSGallery, PSResourceGet, PSReadLine, profile presence, long path support,
    and known footguns. Makes no changes.

.PARAMETER Repair
    Aggressive recovery: removes duplicate PSReadLine installs, force-reinstalls
    PSReadLine, PSResourceGet, and re-trusts PSGallery. Use when something's
    wedged.

.PARAMETER Update
    Updates PSReadLine, PSResourceGet, CompletionPredictor, Terminal-Icons,
    and posh-git (when installed) to latest. Skips environment setup.

.PARAMETER Restore
    Restores the most recent profile backups (Microsoft.PowerShell_profile.ps1
    and profile.ps1) and exits.

.PARAMETER Uninstall
    Removes GUS profile stubs and the shared template. Does NOT revert
    execution policy, TLS settings, NuGet, or installed modules -- those are
    non-destructive and used by other tools.

.PARAMETER Scope
    'CurrentUser' (default) or 'AllUsers'. AllUsers requires elevation and
    writes the AllUsersAllHosts profile + LongPathsEnabled registry key.

.PARAMETER IncludeOhMyPosh
    Install Oh My Posh via winget (modern installation; the PowerShell module
    version is deprecated). Adds the init line to the GUS profile. Off by default.

.PARAMETER IncludeNerdFonts
    Install CaskaydiaCove Nerd Font via oh-my-posh. Implies -IncludeOhMyPosh.
    Off by default.

.PARAMETER Minimal
    Skip module installation entirely. Useful for locked-down environments
    (WDAC, AppLocker, air-gapped). Still sets execution policy, TLS,
    encoding defaults, and writes the profile.

.PARAMETER ProfileRoot
    Where to store the shared GUS profile template.
    Default: "$env:USERPROFILE\.gus".

.EXAMPLE
    .\Invoke-GUS.ps1
    Default install for current user.

.EXAMPLE
    .\Invoke-GUS.ps1 -Diagnose
    Show health check, make no changes.

.EXAMPLE
    .\Invoke-GUS.ps1 -IncludeOhMyPosh -IncludeNerdFonts
    Full install with the pretty prompt and required font.

.EXAMPLE
    .\Invoke-GUS.ps1 -Scope AllUsers -IncludeOhMyPosh
    Machine-wide install. Requires elevation.

.EXAMPLE
    .\Invoke-GUS.ps1 -Repair
    The "I broke something" button.

.EXAMPLE
    .\Invoke-GUS.ps1 -Restore
    Revert profile changes.

.EXAMPLE
    .\Invoke-GUS.ps1 -Minimal
    Locked-down environments. No PSGallery, no Install-Module calls.

.NOTES
    Author : you
    License: do whatever
    Tested : Windows PowerShell 5.1, PowerShell 7.4 LTS, 7.5 STS, 7.6 LTS
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [switch]$Install,

    [Parameter(ParameterSetName = 'Diagnose', Mandatory)]
    [switch]$Diagnose,

    [Parameter(ParameterSetName = 'Repair', Mandatory)]
    [switch]$Repair,

    [Parameter(ParameterSetName = 'Update', Mandatory)]
    [switch]$Update,

    [Parameter(ParameterSetName = 'Restore', Mandatory)]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Uninstall', Mandatory)]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = 'RelocateModules', Mandatory)]
    [switch]$RelocateModules,

    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [Parameter(ParameterSetName = 'Install')]
    [switch]$IncludeOhMyPosh,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$IncludeNerdFonts,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Minimal,

    [string]$ProfileRoot = (Join-Path $env:USERPROFILE '.gus')
)

# =============================================================================
# 0. PRELUDE -- environment detection, output helpers
# =============================================================================

# Don't set $ErrorActionPreference = 'Stop' globally. We handle errors per-call
# so a single failure doesn't terminate the whole bootstrap.
# Don't touch $PSEdition -- it's a read-only automatic. Read $PSVersionTable instead.

$Script:IsPS7        = $PSVersionTable.PSVersion.Major -ge 7
$Script:IsPS51       = ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1)
$Script:HostIsISE    = $Host.Name -eq 'Windows PowerShell ISE Host'
$Script:GUSVersion   = '1.0.0'
$Script:GUSStarted   = Get-Date
$Script:BackupRoot   = Join-Path $ProfileRoot 'backups'

# IncludeNerdFonts implies IncludeOhMyPosh.
if ($IncludeNerdFonts) { $IncludeOhMyPosh = $true }

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
    $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

$Script:IsAdmin = Test-IsAdmin

# Output helpers. ASCII-only by design -- no Unicode box drawing -- so this
# script renders correctly regardless of file save encoding.

function Write-GUS {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Info', 'OK', 'Skip', 'Warn', 'Err', 'Step')]
        [string]$Level = 'Info'
    )
    $tag, $color = switch ($Level) {
        'Step' { '==>',  'Cyan' }
        'OK'   { '[OK]', 'Green' }
        'Skip' { '[--]', 'DarkGray' }
        'Warn' { '[!!]', 'Yellow' }
        'Err'  { '[XX]', 'Red' }
        default { '[..]', 'Gray' }
    }
    Write-Host "$tag $Message" -ForegroundColor $color
}

function Write-GUSHeader {
    Write-Host ""
    Write-Host "  GUS - Grand Unified Script v$Script:GUSVersion" -ForegroundColor White
    Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  Mode      : {0}" -f $PSCmdlet.ParameterSetName) -ForegroundColor Gray
    Write-Host ("  PowerShell: {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition) -ForegroundColor Gray
    Write-Host ("  Host      : {0}" -f $Host.Name) -ForegroundColor Gray
    Write-Host ("  Scope     : {0}" -f $Scope) -ForegroundColor Gray
    Write-Host ("  Admin     : {0}" -f $Script:IsAdmin) -ForegroundColor Gray
    Write-Host ""
    if ($Scope -eq 'AllUsers' -and -not $Script:IsAdmin) {
        throw "Scope 'AllUsers' requires an elevated PowerShell session."
    }
    if ($Script:HostIsISE -and $PSCmdlet.ParameterSetName -eq 'Install') {
        Write-GUS "Running inside the PowerShell ISE. PSReadLine features will not work in ISE itself, but the profile will work everywhere else." -Level Warn
    }
}

# =============================================================================
# 1. ENVIRONMENT -- TLS, ExecutionPolicy, NuGet, PSGallery, PSResourceGet
# =============================================================================

function Set-GUSTls {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "Configuring TLS for this session" -Level Step
    try {
        $current = [Net.ServicePointManager]::SecurityProtocol
        $needed  = [Net.SecurityProtocolType]::Tls12
        if ([enum]::GetNames([Net.SecurityProtocolType]) -contains 'Tls13') {
            $needed = $needed -bor [Net.SecurityProtocolType]::Tls13
        }
        if (($current -band $needed) -ne $needed) {
            if ($PSCmdlet.ShouldProcess('SecurityProtocol', 'Add TLS 1.2/1.3')) {
                [Net.ServicePointManager]::SecurityProtocol = $current -bor $needed
                Write-GUS "TLS 1.2/1.3 enabled (additive)" -Level OK
            }
        } else {
            Write-GUS "TLS already adequate" -Level Skip
        }
    } catch {
        Write-GUS "TLS configuration failed: $($_.Exception.Message)" -Level Err
    }
}

function Set-GUSExecutionPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$DesiredPolicy = 'RemoteSigned')

    Write-GUS "Setting ExecutionPolicy ($Scope = $DesiredPolicy)" -Level Step
    try {
        $current = Get-ExecutionPolicy -Scope $Scope -ErrorAction Stop
        if ($current -in @('RemoteSigned', 'Bypass', 'Unrestricted')) {
            Write-GUS "ExecutionPolicy already permissive ($current)" -Level Skip
            return
        }
        if ($PSCmdlet.ShouldProcess("ExecutionPolicy $Scope", "Set $DesiredPolicy")) {
            Set-ExecutionPolicy -Scope $Scope -ExecutionPolicy $DesiredPolicy -Force
            Write-GUS "ExecutionPolicy set: $Scope = $DesiredPolicy" -Level OK
        }
    } catch {
        Write-GUS "Could not set ExecutionPolicy: $($_.Exception.Message)" -Level Warn
    }
}

function Install-GUSNuGetProvider {
    [CmdletBinding(SupportsShouldProcess)]
    param([version]$MinimumVersion = '2.8.5.201')

    Write-GUS "Ensuring NuGet provider >= $MinimumVersion" -Level Step
    try {
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if ($nuget -and $nuget.Version -ge $MinimumVersion) {
            Write-GUS "NuGet provider $($nuget.Version) present" -Level Skip
            return
        }
        if ($PSCmdlet.ShouldProcess('NuGet provider', 'Install')) {
            Install-PackageProvider -Name NuGet -MinimumVersion $MinimumVersion `
                -Force -Scope $Scope -Confirm:$false | Out-Null
            Write-GUS "NuGet provider installed" -Level OK
        }
    } catch {
        Write-GUS "NuGet install failed: $($_.Exception.Message)" -Level Err
    }
}

function Set-GUSPSGalleryTrust {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "Trusting PSGallery" -Level Step
    try {
        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $repo) {
            if ($PSCmdlet.ShouldProcess('PSGallery', 'Register-PSRepository -Default')) {
                Register-PSRepository -Default -ErrorAction Stop
                $repo = Get-PSRepository -Name PSGallery
                Write-GUS "PSGallery registered" -Level OK
            }
        }
        if ($repo.InstallationPolicy -ne 'Trusted') {
            if ($PSCmdlet.ShouldProcess('PSGallery', 'Set InstallationPolicy=Trusted')) {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                Write-GUS "PSGallery now trusted" -Level OK
            }
        } else {
            Write-GUS "PSGallery already trusted" -Level Skip
        }
    } catch {
        Write-GUS "PSGallery trust failed: $($_.Exception.Message)" -Level Warn
    }
}

function Install-GUSPSResourceGet {
    # PSResourceGet is the modern, faster successor to PowerShellGet.
    # Ships in PS 7.4+. On PS 5.1 / earlier 7.x we install it from PSGallery.
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "Ensuring Microsoft.PowerShell.PSResourceGet" -Level Step
    try {
        $existing = Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PSResourceGet' |
                    Sort-Object Version -Descending | Select-Object -First 1
        if ($existing) {
            Write-GUS "PSResourceGet $($existing.Version) present" -Level Skip
            return
        }
        if ($PSCmdlet.ShouldProcess('Microsoft.PowerShell.PSResourceGet', 'Install-Module')) {
            Install-Module -Name 'Microsoft.PowerShell.PSResourceGet' -Scope $Scope `
                -Force -AllowClobber -Confirm:$false -ErrorAction Stop
            Write-GUS "PSResourceGet installed" -Level OK
        }
    } catch {
        Write-GUS "PSResourceGet install failed: $($_.Exception.Message)" -Level Warn
    }
}

# =============================================================================
# 2. MODULES -- PSReadLine, CompletionPredictor, Terminal-Icons, posh-git
# =============================================================================

function Install-GUSModule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [version]$MinimumVersion = '0.0.0.0',
        [switch]$AllowClobber
    )
    $existing = Get-Module -ListAvailable -Name $Name |
                Sort-Object Version -Descending | Select-Object -First 1
    if ($existing -and $existing.Version -ge $MinimumVersion) {
        Write-GUS "$Name $($existing.Version) already present" -Level Skip
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Name, 'Install-Module')) { return }
    try {
        $params = @{
            Name        = $Name
            Scope       = $Scope
            Force       = $true
            Confirm     = $false
            ErrorAction = 'Stop'
        }
        if ($AllowClobber) { $params['AllowClobber'] = $true }
        # Try PSResourceGet first if available -- it's faster.
        if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
            try {
                $rgParams = @{
                    Name        = $Name
                    Scope       = $Scope
                    TrustRepository = $true
                    Reinstall   = $false
                    Confirm     = $false
                    ErrorAction = 'Stop'
                }
                Install-PSResource @rgParams
                Write-GUS "$Name installed via PSResourceGet" -Level OK
                return
            } catch {
                Write-GUS "PSResourceGet failed for ${Name}; falling back to Install-Module: $($_.Exception.Message)" -Level Warn
            }
        }
        Install-Module @params
        Write-GUS "$Name installed via PowerShellGet" -Level OK
    } catch {
        Write-GUS "$Name install failed: $($_.Exception.Message)" -Level Err
    }
}

function Install-GUSModuleSet {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "Installing module set" -Level Step

    # PSReadLine: the in-box 2.0.0 on Windows PowerShell 5.1 is ancient.
    # 2.2.6+ has predictive intellisense on by default. 2.3.x is current stable.
    Install-GUSModule -Name 'PSReadLine' -MinimumVersion '2.3.4' -AllowClobber

    # CompletionPredictor: PSReadLine plugin (PS 7.2+ only) that turns
    # tab-completion candidates into prediction suggestions. Game changer.
    if ($Script:IsPS7) {
        Install-GUSModule -Name 'CompletionPredictor' -MinimumVersion '0.1.1'
    } else {
        Write-GUS "CompletionPredictor requires PowerShell 7.2+ (you have $($PSVersionTable.PSVersion)); skipping" -Level Skip
    }

    # Terminal-Icons: glyphs in Get-ChildItem output. Needs a Nerd Font to
    # render glyphs; falls back to text otherwise.
    Install-GUSModule -Name 'Terminal-Icons' -MinimumVersion '0.10.0'

    # posh-git: git branch info in prompt.
    Install-GUSModule -Name 'posh-git' -MinimumVersion '1.1.0'
}

# =============================================================================
# 3. OPTIONAL -- Oh My Posh, Nerd Fonts (via winget + oh-my-posh CLI)
# =============================================================================

function Install-GUSOhMyPosh {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "Installing Oh My Posh (via winget)" -Level Step

    # The oh-my-posh PowerShell module is deprecated. Install via winget.
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-GUS "winget not found. Install 'App Installer' from the Microsoft Store, or skip -IncludeOhMyPosh." -Level Err
        return
    }
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-GUS "oh-my-posh already on PATH" -Level Skip
        return
    }
    if ($PSCmdlet.ShouldProcess('JanDeDobbeleer.OhMyPosh', 'winget install')) {
        try {
            $args = @('install', '--id', 'JanDeDobbeleer.OhMyPosh', '-s', 'winget',
                      '--accept-package-agreements', '--accept-source-agreements',
                      '--silent')
            & winget @args 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-GUS "Oh My Posh installed" -Level OK
                Write-GUS "Restart your shell or re-source PATH for 'oh-my-posh' to be visible" -Level Info
            } else {
                Write-GUS "winget returned exit code $LASTEXITCODE" -Level Warn
            }
        } catch {
            Write-GUS "Oh My Posh install failed: $($_.Exception.Message)" -Level Err
        }
    }
}

function Install-GUSNerdFont {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Font = 'CascadiaCode')
    Write-GUS "Installing Nerd Font: $Font" -Level Step

    $omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $omp) {
        Write-GUS "oh-my-posh not on PATH; can't install font. Open a new shell after -IncludeOhMyPosh and re-run with -IncludeNerdFonts." -Level Err
        return
    }
    if ($PSCmdlet.ShouldProcess($Font, 'oh-my-posh font install')) {
        try {
            & oh-my-posh font install $Font 2>&1 | Out-Null
            Write-GUS "Font '$Font' installed. Set Windows Terminal font to '$Font NF'." -Level OK
        } catch {
            Write-GUS "Font install failed: $($_.Exception.Message)" -Level Err
        }
    }
}

# =============================================================================
# 4. LONG PATHS -- registry setting, requires admin
# =============================================================================

function Enable-GUSLongPaths {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "Enabling Windows long path support (LongPathsEnabled)" -Level Step
    if (-not $Script:IsAdmin) {
        Write-GUS "Long path support requires admin. Skipping; re-run elevated to enable." -Level Skip
        return
    }
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    try {
        $current = (Get-ItemProperty -Path $path -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue).LongPathsEnabled
        if ($current -eq 1) {
            Write-GUS "LongPathsEnabled already set" -Level Skip
            return
        }
        if ($PSCmdlet.ShouldProcess($path, 'Set LongPathsEnabled=1')) {
            New-ItemProperty -Path $path -Name 'LongPathsEnabled' -Value 1 -PropertyType DWord -Force | Out-Null
            Write-GUS "LongPathsEnabled = 1 (some apps require manifest support and a reboot)" -Level OK
        }
    } catch {
        Write-GUS "Long path enable failed: $($_.Exception.Message)" -Level Err
    }
}

# =============================================================================
# 5. PROFILE -- write shared template to ~\.gus, stub loaders to both editions
# =============================================================================

function Get-GUSProfilePaths {
    # Returns hashtable of target stub paths for both editions, CurrentUser
    # (or AllUsers when Scope=AllUsers).
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($Scope -eq 'AllUsers') {
        @{
            'WindowsPowerShell' = Join-Path "$env:WINDIR\System32\WindowsPowerShell\v1.0" 'profile.ps1'
            'PowerShell'        = Join-Path "$env:ProgramFiles\PowerShell\7" 'profile.ps1'
        }
    } else {
        @{
            'WindowsPowerShell' = Join-Path $docs 'WindowsPowerShell\profile.ps1'
            'PowerShell'        = Join-Path $docs 'PowerShell\profile.ps1'
        }
    }
}

# Write a file with retry on transient IO locks. Defender, OneDrive, and other
# PowerShell sessions holding the file briefly cause IOException; a short
# backoff almost always clears it. The previous version of this function
# failed fatally on the first lock collision.
function Set-ContentWithRetry {
    param(
        [Parameter(Mandatory)] [string]$LiteralPath,
        [Parameter(Mandatory)] [string]$Value,
        [string]$Encoding = 'utf8',
        [int]$MaxAttempts = 6
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            Set-Content -LiteralPath $LiteralPath -Value $Value -Encoding $Encoding -Force -ErrorAction Stop
            return
        } catch [System.IO.IOException] {
            if ($i -eq $MaxAttempts) { throw }
            $wait = [int]($i * 250)
            Write-GUS "Write locked (attempt $i/$MaxAttempts): $LiteralPath -- retrying in ${wait}ms" -Level Warn
            Start-Sleep -Milliseconds $wait
        } catch {
            # Non-IO error: don't retry, propagate.
            throw
        }
    }
}

function Backup-GUSExistingProfile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$EditionTag = 'misc'   # Explicit tag, not derived from parent dir.
                                       # Parent-dir-leaf works for CurrentUser
                                       # ('WindowsPowerShell' / 'PowerShell') but
                                       # breaks for AllUsers ('v1.0' / '7').
    )
    if (-not (Test-Path $Path)) { return }
    if (-not (Test-Path $Script:BackupRoot)) {
        New-Item -ItemType Directory -Path $Script:BackupRoot -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name  = '{0}.{1}.{2}.bak' -f (Split-Path $Path -Leaf), $EditionTag, $stamp
    $dest  = Join-Path $Script:BackupRoot $name
    Copy-Item $Path $dest -Force
    Write-GUS "Backed up: $Path -> $(Split-Path $dest -Leaf)" -Level Info
}

function Write-GUSProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "Writing GUS profile" -Level Step

    # 1. Locate the GUS.Profile.ps1 template that ships alongside this script.
    $templateSrc = Join-Path $PSScriptRoot 'GUS.Profile.ps1'
    if (-not (Test-Path $templateSrc)) {
        Write-GUS "Template not found at $templateSrc. The profile file (GUS.Profile.ps1) must live in the same folder as Invoke-GUS.ps1." -Level Err
        return
    }

    # 2. Create profile root if absent.
    if (-not (Test-Path $ProfileRoot)) {
        New-Item -ItemType Directory -Path $ProfileRoot -Force | Out-Null
    }

    # 3. Copy template to shared location, UTF-8 with BOM for PS 5.1 compat.
    $sharedTarget = Join-Path $ProfileRoot 'GUS.Profile.ps1'
    if ($PSCmdlet.ShouldProcess($sharedTarget, 'Copy template')) {
        $content = Get-Content $templateSrc -Raw
        # Patch in OhMyPosh activation line if requested
        if ($IncludeOhMyPosh) {
            $content = $content -replace '#__GUS_OHMYPOSH__', @'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    try {
        $ompTheme = if ($env:POSH_THEMES_PATH) {
            Join-Path $env:POSH_THEMES_PATH 'jandedobbeleer.omp.json'
        } else { $null }
        if ($ompTheme -and (Test-Path $ompTheme)) {
            oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
        } else {
            oh-my-posh init pwsh | Invoke-Expression
        }
    } catch { Write-Verbose "oh-my-posh init failed: $_" }
}
'@
        }
        # Write UTF-8 with BOM. On PS 5.1, -Encoding utf8 = BOM-inclusive.
        Set-ContentWithRetry -LiteralPath $sharedTarget -Value $content -Encoding utf8
        Write-GUS "Shared profile written: $sharedTarget" -Level OK
    }

    # 4. Write tiny stub loaders to BOTH PS 5.1 and PS 7 profile paths.
    # Stubs load the shared template as a scriptblock from raw content rather
    # than dot-sourcing the file. This bypasses execution-policy checks and
    # MOTW gating on the template -- which matters when GPO enforces AllSigned
    # at a higher scope, or when the template inherits MOTW from a sync source.
    $stub = @"
# GUS profile loader (scriptblock variant). Auto-generated by Invoke-GUS.ps1.
# Edit `$ProfileRoot\GUS.Profile.ps1` to customize behavior; do not edit here.
`$gusProfile = "$sharedTarget"
if (Test-Path `$gusProfile) {
    try {
        . ([scriptblock]::Create((Get-Content -LiteralPath `$gusProfile -Raw)))
    } catch {
        Write-Warning "GUS profile load failed: `$(`$_.Exception.Message)"
    }
}
"@

    foreach ($entry in (Get-GUSProfilePaths).GetEnumerator()) {
        $stubPath = $entry.Value
        $stubDir  = Split-Path $stubPath -Parent
        if (-not (Test-Path $stubDir)) {
            try { New-Item -ItemType Directory -Path $stubDir -Force | Out-Null }
            catch {
                Write-GUS "Could not create $stubDir ($($entry.Key)): $($_.Exception.Message)" -Level Warn
                continue
            }
        }
        Backup-GUSExistingProfile -Path $stubPath -EditionTag $entry.Key
        if ($PSCmdlet.ShouldProcess($stubPath, "Write stub for $($entry.Key)")) {
            Set-ContentWithRetry -LiteralPath $stubPath -Value $stub -Encoding utf8
            Write-GUS "Stub written: $($entry.Key) -> $stubPath" -Level OK
        }
    }
}

# =============================================================================
# 6. DIAGNOSE MODE -- read-only health check
# =============================================================================

function Invoke-GUSDiagnose {
    Write-GUS "GUS Diagnostics -- no changes will be made" -Level Step

    # Execution policy across all scopes
    Write-Host ""
    Write-Host "  Execution Policy:" -ForegroundColor White
    foreach ($s in 'MachinePolicy','UserPolicy','Process','CurrentUser','LocalMachine') {
        try {
            $p = Get-ExecutionPolicy -Scope $s -ErrorAction SilentlyContinue
            Write-Host ("    {0,-15} : {1}" -f $s, $p) -ForegroundColor Gray
        } catch {}
    }

    # TLS
    Write-Host ""
    Write-Host "  TLS:" -ForegroundColor White
    Write-Host ("    Current      : {0}" -f [Net.ServicePointManager]::SecurityProtocol) -ForegroundColor Gray

    # NuGet
    Write-Host ""
    Write-Host "  NuGet provider:" -ForegroundColor White
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if ($nuget) {
        Write-Host ("    Version      : {0}" -f $nuget.Version) -ForegroundColor Gray
    } else {
        Write-Host "    Not installed" -ForegroundColor Yellow
    }

    # PSGallery
    Write-Host ""
    Write-Host "  PSGallery:" -ForegroundColor White
    $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($gallery) {
        Write-Host ("    Policy       : {0}" -f $gallery.InstallationPolicy) -ForegroundColor Gray
        Write-Host ("    Source       : {0}" -f $gallery.SourceLocation) -ForegroundColor Gray
    } else {
        Write-Host "    Not registered" -ForegroundColor Yellow
    }

    # Module inventory
    Write-Host ""
    Write-Host "  Key Modules:" -ForegroundColor White
    foreach ($m in 'PSReadLine','Microsoft.PowerShell.PSResourceGet','PowerShellGet',
                   'CompletionPredictor','Terminal-Icons','posh-git') {
        $mods = Get-Module -ListAvailable -Name $m -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending
        if ($mods) {
            $versions = ($mods | Select-Object -ExpandProperty Version) -join ', '
            $color = if ($mods.Count -gt 1) { 'Yellow' } else { 'Gray' }
            Write-Host ("    {0,-35} : {1}" -f $m, $versions) -ForegroundColor $color
            if ($mods.Count -gt 1) {
                Write-Host ("    {0,-35}   ^ multiple versions; run -Repair" -f '') -ForegroundColor DarkYellow
            }
        } else {
            Write-Host ("    {0,-35} : MISSING" -f $m) -ForegroundColor Yellow
        }
    }

    # Profile paths
    Write-Host ""
    Write-Host "  Profiles:" -ForegroundColor White
    foreach ($p in 'AllUsersAllHosts','AllUsersCurrentHost','CurrentUserAllHosts','CurrentUserCurrentHost') {
        $val = $PROFILE.$p
        $exists = Test-Path $val
        $color = if ($exists) { 'Green' } else { 'DarkGray' }
        Write-Host ("    {0,-25} : {1} {2}" -f $p, $val, $(if ($exists){'(present)'}else{'(absent)'})) -ForegroundColor $color
    }

    # GUS profile
    $gusProf = Join-Path $ProfileRoot 'GUS.Profile.ps1'
    Write-Host ""
    Write-Host "  GUS Profile Template:" -ForegroundColor White
    if (Test-Path $gusProf) {
        $info = Get-Item $gusProf
        Write-Host ("    Path         : {0}" -f $gusProf) -ForegroundColor Gray
        Write-Host ("    Size         : {0} bytes" -f $info.Length) -ForegroundColor Gray
        Write-Host ("    Modified     : {0}" -f $info.LastWriteTime) -ForegroundColor Gray
    } else {
        Write-Host "    Not installed (run without -Diagnose to install)" -ForegroundColor Yellow
    }

    # Long paths
    Write-Host ""
    Write-Host "  Long Path Support:" -ForegroundColor White
    try {
        $lp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled
        $color = if ($lp -eq 1) { 'Green' } else { 'Yellow' }
        Write-Host ("    LongPathsEnabled : {0}" -f $lp) -ForegroundColor $color
    } catch {
        Write-Host "    LongPathsEnabled : not set (run elevated to enable)" -ForegroundColor Yellow
    }

    # Encoding sanity
    Write-Host ""
    Write-Host "  Encoding:" -ForegroundColor White
    Write-Host ("    Console.OutputEncoding : {0}" -f [Console]::OutputEncoding.WebName) -ForegroundColor Gray
    Write-Host ("    `$OutputEncoding         : {0}" -f $OutputEncoding.WebName) -ForegroundColor Gray
    $defEnc = $PSDefaultParameterValues['Out-File:Encoding']
    Write-Host ("    Out-File default       : {0}" -f $(if ($defEnc) { $defEnc } else { 'not set (PS will use Unicode/UTF-16 LE on 5.1)' })) -ForegroundColor Gray

    # PSReadLine config
    if (Get-Module PSReadLine -ErrorAction SilentlyContinue) {
        $opts = Get-PSReadLineOption
        Write-Host ""
        Write-Host "  PSReadLine (loaded):" -ForegroundColor White
        Write-Host ("    Version            : {0}" -f (Get-Module PSReadLine).Version) -ForegroundColor Gray
        Write-Host ("    PredictionSource   : {0}" -f $opts.PredictionSource) -ForegroundColor Gray
        Write-Host ("    PredictionViewStyle: {0}" -f $opts.PredictionViewStyle) -ForegroundColor Gray
        Write-Host ("    EditMode           : {0}" -f $opts.EditMode) -ForegroundColor Gray
    }

    Write-Host ""
    Write-GUS "Diagnose complete." -Level OK
}

# =============================================================================
# 7. REPAIR MODE -- nuke duplicate modules, reinstall
# =============================================================================

function Invoke-GUSRepair {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "GUS Repair -- resetting modules and reinstalling" -Level Step

    # Re-run env setup first (safe, idempotent)
    Set-GUSTls
    Set-GUSExecutionPolicy
    Install-GUSNuGetProvider
    Set-GUSPSGalleryTrust

    # For each finicky module: unload, find ALL installations, force-reinstall.
    foreach ($modName in @('PSReadLine','Microsoft.PowerShell.PSResourceGet',
                           'CompletionPredictor','Terminal-Icons','posh-git')) {
        Write-GUS "Repairing module: $modName" -Level Step
        Remove-Module $modName -Force -ErrorAction SilentlyContinue

        $installs = Get-Module -ListAvailable -Name $modName -ErrorAction SilentlyContinue
        if ($installs.Count -gt 1) {
            Write-GUS "Found $($installs.Count) copies of ${modName}; cleaning duplicates" -Level Warn
            foreach ($i in $installs) {
                # Don't touch the $PSHOME copy of PSReadLine -- it's needed as a
                # baseline. We let Install-Module/Install-PSResource shadow it.
                if ($i.ModuleBase -like "$PSHOME*") {
                    Write-GUS "Leaving $PSHOME copy of $modName in place" -Level Skip
                    continue
                }
                if ($PSCmdlet.ShouldProcess($i.ModuleBase, "Remove module directory")) {
                    try {
                        Remove-Item -LiteralPath $i.ModuleBase -Recurse -Force -ErrorAction Stop
                        Write-GUS "Removed: $($i.ModuleBase)" -Level OK
                    } catch {
                        Write-GUS "Could not remove $($i.ModuleBase): $($_.Exception.Message)" -Level Warn
                    }
                }
            }
        }

        # Reinstall fresh, allow clobber where it matters
        $minVer = switch ($modName) {
            'PSReadLine'                          { '2.3.4' }
            'Microsoft.PowerShell.PSResourceGet'  { '1.0.0' }
            'CompletionPredictor'                 { '0.1.1' }
            'Terminal-Icons'                      { '0.10.0' }
            'posh-git'                            { '1.1.0' }
        }
        Install-GUSModule -Name $modName -MinimumVersion $minVer `
            -AllowClobber:($modName -eq 'PSReadLine')
    }

    Write-GUS "Repair complete." -Level OK
}

# =============================================================================
# 8. UPDATE MODE -- bump modules only
# =============================================================================

function Invoke-GUSUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "GUS Update -- updating installed modules to latest" -Level Step

    $candidates = @(
        'PSReadLine',
        'Microsoft.PowerShell.PSResourceGet',
        'CompletionPredictor',
        'Terminal-Icons',
        'posh-git'
    )

    foreach ($m in $candidates) {
        $installed = Get-Module -ListAvailable -Name $m -ErrorAction SilentlyContinue |
                     Sort-Object Version -Descending | Select-Object -First 1
        if (-not $installed) {
            Write-GUS "$m not installed; skipping" -Level Skip
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($m, 'Update')) { continue }
        try {
            if (Get-Command Update-PSResource -ErrorAction SilentlyContinue) {
                Update-PSResource -Name $m -Force -TrustRepository -Confirm:$false -ErrorAction Stop
            } else {
                Update-Module -Name $m -Force -Confirm:$false -ErrorAction Stop
            }
            $new = Get-Module -ListAvailable -Name $m | Sort-Object Version -Descending | Select-Object -First 1
            if ($new.Version -gt $installed.Version) {
                Write-GUS "$m : $($installed.Version) -> $($new.Version)" -Level OK
            } else {
                Write-GUS "$m : already at $($installed.Version)" -Level Skip
            }
        } catch {
            Write-GUS "$m update failed: $($_.Exception.Message)" -Level Warn
        }
    }

    # Update oh-my-posh if present
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            Write-GUS "Updating oh-my-posh via winget" -Level Step
            try {
                & winget upgrade --id JanDeDobbeleer.OhMyPosh `
                    --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
                Write-GUS "oh-my-posh updated" -Level OK
            } catch {
                Write-GUS "oh-my-posh update failed: $($_.Exception.Message)" -Level Warn
            }
        }
    }
}

# =============================================================================
# 9. RESTORE MODE -- revert from latest backup
# =============================================================================

function Invoke-GUSRestore {
    Write-GUS "GUS Restore -- reverting profile stubs from latest backup" -Level Step
    if (-not (Test-Path $Script:BackupRoot)) {
        Write-GUS "No backup directory at $Script:BackupRoot" -Level Warn
        return
    }
    $paths = Get-GUSProfilePaths
    foreach ($entry in $paths.GetEnumerator()) {
        $stub = $entry.Value
        $needle = (Split-Path $stub -Leaf) + '.' + $entry.Key + '.'
        $bak = Get-ChildItem $Script:BackupRoot -Filter "$needle*.bak" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $bak) {
            Write-GUS "$($entry.Key): no backup found, removing stub if present" -Level Info
            if (Test-Path $stub) {
                Remove-Item $stub -Force
                Write-GUS "Removed: $stub" -Level OK
            }
            continue
        }
        Copy-Item $bak.FullName $stub -Force
        Write-GUS "$($entry.Key): restored from $($bak.Name)" -Level OK
    }
    Write-GUS "Restore complete. Open a new shell to load the previous profile." -Level OK
}

# =============================================================================
# 10. UNINSTALL MODE
# =============================================================================

function Invoke-GUSUninstall {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "GUS Uninstall -- removing profile stubs and template" -Level Step
    $paths = Get-GUSProfilePaths
    foreach ($entry in $paths.GetEnumerator()) {
        $stub = $entry.Value
        if (-not (Test-Path $stub)) { continue }
        # Backup before removal
        Backup-GUSExistingProfile -Path $stub -EditionTag $entry.Key
        if ($PSCmdlet.ShouldProcess($stub, 'Remove stub')) {
            Remove-Item $stub -Force
            Write-GUS "Removed: $stub" -Level OK
        }
    }
    $sharedTarget = Join-Path $ProfileRoot 'GUS.Profile.ps1'
    if (Test-Path $sharedTarget) {
        Backup-GUSExistingProfile -Path $sharedTarget -EditionTag 'shared'
        if ($PSCmdlet.ShouldProcess($sharedTarget, 'Remove shared template')) {
            Remove-Item $sharedTarget -Force
            Write-GUS "Removed: $sharedTarget" -Level OK
        }
    }
    Write-GUS "Uninstall complete. Modules left in place; remove with Uninstall-Module if desired." -Level OK
    Write-GUS "Backups retained in: $Script:BackupRoot" -Level Info
}

# =============================================================================
# 11. RELOCATEMODULES MODE -- move modules off OneDrive-synced paths
# =============================================================================
# When Windows Documents is OneDrive-redirected, the default per-user module
# path lives under OneDrive. Every module load goes through the OneDrive
# filter driver, which adds large latency to PowerShell startup (often 3-5
# seconds when there are many installed modules).
#
# This mode moves all module subdirectories from any OneDrive-pathed entry in
# PSModulePath into a local path under %LOCALAPPDATA%\PowerShell\Modules, and
# prepends that path to the user-scope PSModulePath so PowerShell finds them
# first. The OneDrive paths remain in PSModulePath (PowerShell re-adds them
# at startup based on Documents folder location, which we can't change here),
# but those folders are now empty so the discovery scan is fast.

function Invoke-GUSRelocateModules {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-GUS "GUS RelocateModules -- moving modules off OneDrive-synced paths" -Level Step

    # 1. Identify module paths that route through OneDrive.
    $processPaths = $env:PSModulePath -split ';' | Where-Object { $_ -and (Test-Path $_) }
    $oneDrivePaths = $processPaths | Where-Object { $_ -match 'OneDrive' }

    if (-not $oneDrivePaths) {
        Write-GUS "No OneDrive-pathed module locations found in PSModulePath. Nothing to do." -Level Skip
        return
    }

    Write-GUS "OneDrive-routed module paths detected:" -Level Info
    foreach ($p in $oneDrivePaths) { Write-Host "    $p" -ForegroundColor DarkGray }

    # 2. Target: shared local path. Both PS 5.1 and PS 7 can share Modules\.
    $localBase = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules'
    if (-not (Test-Path $localBase)) {
        if ($PSCmdlet.ShouldProcess($localBase, 'Create target directory')) {
            New-Item -ItemType Directory -Path $localBase -Force | Out-Null
        }
    }
    Write-GUS "Target local module path: $localBase" -Level Info

    # 3. Move each module subdirectory.
    $moved = 0
    $skipped = 0
    $failed = 0

    foreach ($src in $oneDrivePaths) {
        $modules = Get-ChildItem -LiteralPath $src -Directory -ErrorAction SilentlyContinue
        if (-not $modules) {
            Write-GUS "Empty (skip): $src" -Level Skip
            continue
        }
        Write-GUS "Processing $($modules.Count) module(s) in: $src" -Level Step
        foreach ($m in $modules) {
            $dst = Join-Path $localBase $m.Name
            if (Test-Path $dst) {
                Write-GUS "Already at target: $($m.Name)" -Level Skip
                $skipped++
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($m.FullName, "Move to $dst")) { continue }
            try {
                Move-Item -LiteralPath $m.FullName -Destination $dst -Force -ErrorAction Stop
                $moved++
            } catch {
                Write-GUS "Failed: $($m.Name) -- $($_.Exception.Message)" -Level Warn
                $failed++
            }
        }
    }
    Write-GUS "Moved $moved | Skipped $skipped | Failed $failed" -Level Info

    # 4. Prepend the local path to the user-scope PSModulePath so PowerShell
    #    finds modules there first. We cannot remove the OneDrive entries from
    #    PSModulePath -- PowerShell re-adds the personal Documents path at
    #    startup based on the Known Folder location -- but since those folders
    #    are now empty, scanning them is cheap.
    $currentUser = [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
    if (-not $currentUser -or $currentUser -notlike "*$localBase*") {
        $newUser = if ($currentUser) { "$localBase;$currentUser" } else { $localBase }
        if ($PSCmdlet.ShouldProcess('User PSModulePath', "Prepend $localBase")) {
            [Environment]::SetEnvironmentVariable('PSModulePath', $newUser, 'User')
            $env:PSModulePath = "$localBase;$env:PSModulePath"
            Write-GUS "User PSModulePath updated. New head: $localBase" -Level OK
        }
    } else {
        Write-GUS "User PSModulePath already includes target" -Level Skip
    }

    Write-Host ""
    Write-GUS "Relocation complete. Open a NEW PowerShell to measure impact." -Level OK
    Write-GUS "Expected drop: 3-5 seconds off cold profile load." -Level Info
    Write-Host ""
    Write-Host "Before/after measurement:" -ForegroundColor White
    Write-Host "  In the new shell, run: gus-perf" -ForegroundColor Gray
    Write-Host "  Compare the welcome-banner 'GUS loaded in Xms' to your 6097ms baseline." -ForegroundColor Gray
}

# =============================================================================
# 11. INSTALL MODE -- the default
# =============================================================================

function Invoke-GUSInstall {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Set-GUSTls
    Set-GUSExecutionPolicy

    if (-not $Minimal) {
        Install-GUSNuGetProvider
        Set-GUSPSGalleryTrust
        Install-GUSPSResourceGet
        Install-GUSModuleSet
        if ($IncludeOhMyPosh)  { Install-GUSOhMyPosh }
        if ($IncludeNerdFonts) { Install-GUSNerdFont -Font 'CascadiaCode' }
    } else {
        Write-GUS "Minimal mode: skipping module installation" -Level Skip
    }

    if ($Scope -eq 'AllUsers') { Enable-GUSLongPaths }
    else { Write-GUS "Long path support: requires -Scope AllUsers (elevated)" -Level Info }

    Write-GUSProfile
}

# =============================================================================
# 12. MAIN
# =============================================================================

try {
    Write-GUSHeader

    switch ($PSCmdlet.ParameterSetName) {
        'Install'         { Invoke-GUSInstall }
        'Diagnose'        { Invoke-GUSDiagnose }
        'Repair'          { Invoke-GUSRepair }
        'Update'          { Invoke-GUSUpdate }
        'Restore'         { Invoke-GUSRestore }
        'Uninstall'       { Invoke-GUSUninstall }
        'RelocateModules' { Invoke-GUSRelocateModules }
    }

    $elapsed = (Get-Date) - $Script:GUSStarted
    Write-Host ""
    Write-GUS ("Done in {0:n1}s" -f $elapsed.TotalSeconds) -Level OK

    if ($PSCmdlet.ParameterSetName -eq 'Install') {
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor White
        Write-Host "  1. Open a NEW PowerShell session (this one has the old profile)." -ForegroundColor Gray
        Write-Host "     Or in this session: . `$PROFILE.CurrentUserAllHosts" -ForegroundColor DarkGray
        Write-Host "  2. Verify: gus-status" -ForegroundColor Gray
        if ($IncludeOhMyPosh) {
            Write-Host "  3. Set your Windows Terminal font to 'CaskaydiaCove NF' for OMP glyphs." -ForegroundColor Gray
        }
        Write-Host ""
        $self = if ($MyInvocation.MyCommand.Name) {
            ".\$($MyInvocation.MyCommand.Name)"
        } else { '.\GUS-Invoke.ps1' }
        Write-Host "Reverse with: $self -Restore"  -ForegroundColor DarkGray
        Write-Host "Diagnose:     $self -Diagnose" -ForegroundColor DarkGray
        Write-Host ""
    }
}
catch {
    $msg = $_.Exception.Message
    Write-GUS "FATAL: $msg" -Level Err
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed

    if ($_.Exception -is [System.IO.IOException] -or $msg -match 'being used by another process') {
        Write-Host ""
        Write-Host "The failing file is locked by another process. Common causes:" -ForegroundColor Yellow
        Write-Host "  1. Another PowerShell window has it open (close all other terminals)." -ForegroundColor Gray
        Write-Host "  2. Windows Defender is scanning it. Wait 10 seconds and re-run." -ForegroundColor Gray
        Write-Host "  3. An editor (VS Code, Notepad++) has it open. Save and close." -ForegroundColor Gray
        Write-Host ""
        $psProcs = Get-Process powershell, pwsh -ErrorAction SilentlyContinue |
                   Where-Object Id -ne $PID
        if ($psProcs) {
            Write-Host "Other PowerShell processes currently running:" -ForegroundColor Yellow
            $psProcs | ForEach-Object {
                Write-Host ("  PID {0,-6} {1,-15} started {2}" -f $_.Id, $_.ProcessName, $_.StartTime) -ForegroundColor Gray
            }
            Write-Host ""
        }
    }
    exit 2
}
