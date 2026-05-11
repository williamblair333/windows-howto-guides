# =============================================================================
# GUS Profile - Grand Unified Script profile template
# =============================================================================
# This file is loaded by stubs in both Windows PowerShell 5.1 and PowerShell 7
# profile locations. Editing this file changes behavior in BOTH editions.
#
# To bypass the profile for one session: pwsh -NoProfile (or powershell -NoProfile)
# To edit:   edit-profile     (function defined below)
# To reload: reload-profile   (function defined below)
# To diag:   gus-status
# =============================================================================

# Bail out cleanly inside the ISE. ISE doesn't load PSReadLine, has its own
# console host, and chokes on several optimizations below. The very few
# functions below that DO work in ISE remain available; the rest are skipped.
$Script:InISE = $Host.Name -eq 'Windows PowerShell ISE Host'
$Script:GUSLoadStart = [System.Diagnostics.Stopwatch]::StartNew()

# -----------------------------------------------------------------------------
# 0. EDITION AWARENESS
# -----------------------------------------------------------------------------
# Read $PSVersionTable, never assign to $PSEdition (read-only automatic).
$Script:IsPS7  = $PSVersionTable.PSVersion.Major -ge 7
$Script:IsPS51 = ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1)

# -----------------------------------------------------------------------------
# 1. ENCODING - the single biggest source of "why does my script break in CI"
# -----------------------------------------------------------------------------
# Goal: UTF-8 everywhere. Console in, console out, pipeline, default file
# output. On PS 7+ most of these are already correct; on PS 5.1 every one
# of them needs explicit fixing.

try { [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false) } catch {}
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# $PSDefaultParameterValues fixes the file-write cmdlets. On PS 5.1, 'utf8'
# means UTF-8-with-BOM (the universally-readable choice). On PS 7+, 'utf8'
# is BOM-less; use 'utf8BOM' if you specifically need a BOM there.
$PSDefaultParameterValues['Out-File:Encoding']            = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding']         = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding']         = 'utf8'
$PSDefaultParameterValues['Export-Csv:Encoding']          = 'utf8'
$PSDefaultParameterValues['Export-Csv:NoTypeInformation'] = $true
$PSDefaultParameterValues['*-Json:Depth']                 = 10

# OEM codepage 65001 for native commands (ipconfig, nslookup, openssl, etc.)
# so their output round-trips into PowerShell strings without mojibake.
# Skip the shell-out if the console is already UTF-8 (faster cold-load).
# Skip in ISE entirely (no console).
if (-not $Script:InISE -and [Console]::OutputEncoding.CodePage -ne 65001) {
    try { $null = chcp.com 65001 2>$null } catch {}
}

# -----------------------------------------------------------------------------
# 2. PERFORMANCE HYGIENE
# -----------------------------------------------------------------------------
# $ProgressPreference = 'SilentlyContinue' is the single biggest perceived
# speedup. Invoke-WebRequest in PS 5.1 is ~50x faster without the progress
# overhead. Local-only-override pattern:
#     $script:OriginalProgress = $ProgressPreference
#     $ProgressPreference = 'Continue'
#     try { Invoke-WebRequest ... } finally { $ProgressPreference = $script:OriginalProgress }
$ProgressPreference = 'SilentlyContinue'

# DO NOT set $ErrorActionPreference = 'Stop' here. It makes interactive use
# painful -- every typo in the console becomes a terminating error. Set it
# per-script via [CmdletBinding()] or by passing -ErrorAction Stop on the
# specific calls you care about.

# -----------------------------------------------------------------------------
# 3. TLS - additive
# -----------------------------------------------------------------------------
try {
    $sec = [Net.ServicePointManager]::SecurityProtocol
    $tls = [Net.SecurityProtocolType]::Tls12
    if ([enum]::GetNames([Net.SecurityProtocolType]) -contains 'Tls13') {
        $tls = $tls -bor [Net.SecurityProtocolType]::Tls13
    }
    [Net.ServicePointManager]::SecurityProtocol = $sec -bor $tls
} catch {}

# -----------------------------------------------------------------------------
# 4. PSReadLine
# -----------------------------------------------------------------------------
# The in-box PSReadLine on Windows PowerShell 5.1 is 2.0.0 and is loaded from
# $PSHOME BEFORE this profile runs. To use a newer copy we have to find and
# Import-Module the version installed under Documents\WindowsPowerShell\Modules.

if (-not $Script:InISE) {
    $prl = Get-Module -ListAvailable PSReadLine |
           Sort-Object Version -Descending | Select-Object -First 1
    if ($prl -and (Get-Module PSReadLine).Version -lt $prl.Version) {
        try { Import-Module $prl.Path -Force -ErrorAction Stop } catch {}
    }

    if (Get-Module PSReadLine) {
        # Editing & history
        Set-PSReadLineOption -EditMode Windows
        Set-PSReadLineOption -BellStyle None
        Set-PSReadLineOption -HistoryNoDuplicates:$true
        Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
        Set-PSReadLineOption -MaximumHistoryCount 20000
        Set-PSReadLineOption -ShowToolTips:$true

        # Predictive IntelliSense.
        # PSReadLine 2.2.6+ enables History prediction by default. We force
        # HistoryAndPlugin (where plugins exist, i.e. PS 7.2+) and ListView.
        try {
            if ($Script:IsPS7) {
                Set-PSReadLineOption -PredictionSource HistoryAndPlugin
            } else {
                Set-PSReadLineOption -PredictionSource History
            }
            Set-PSReadLineOption -PredictionViewStyle ListView
        } catch {
            try { Set-PSReadLineOption -PredictionSource History } catch {}
        }

        # CompletionPredictor: PSReadLine plugin (PS 7.2+ only). Folds the
        # tab-completion candidates into the prediction list. Huge UX win.
        if ($Script:IsPS7 -and (Get-Module -ListAvailable CompletionPredictor)) {
            try { Import-Module CompletionPredictor -ErrorAction Stop } catch {}
        }

        # Don't pollute history with anything that looks like a secret.
        Set-PSReadLineOption -AddToHistoryHandler {
            param([string]$line)
            $patterns = @(
                '(?i)\b(password|passwd|pwd|secret|token|apikey|api[_-]?key|connectionstring|conn[_-]?str)\s*[:=]',
                '(?i)\b(bearer|authorization)\s+[A-Za-z0-9+/=._-]{8,}',
                '\b[A-Za-z0-9]{40,}\b'   # heuristic for raw tokens
            )
            foreach ($p in $patterns) { if ($line -match $p) { return $false } }
            return $true
        }

        # Key bindings: arrow keys do prefix history search; Tab = menu complete.
        # These match what most people expect from bash/zsh.
        Set-PSReadLineKeyHandler -Key UpArrow         -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow       -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Key Tab             -Function MenuComplete
        Set-PSReadLineKeyHandler -Key Ctrl+d          -Function DeleteCharOrExit
        Set-PSReadLineKeyHandler -Key Ctrl+w          -Function BackwardDeleteWord
        Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
        Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow  -Function BackwardWord
        Set-PSReadLineKeyHandler -Key F2              -Function SwitchPredictionView

        # Smart-quote completion: `"` inserts a pair and moves cursor between them.
        Set-PSReadLineKeyHandler -Key '"' -BriefDescription SmartInsertQuote `
            -LongDescription 'Insert paired quotes, or wrap selection' `
            -ScriptBlock {
                param($key, $arg)
                $line = $null; $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
                if ($line[$cursor] -eq $key.KeyChar) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                } else {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$($key.KeyChar)")
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                }
            }

        # Readable colors on dark backgrounds. Skipped on PSReadLine < 2.1.
        try {
            Set-PSReadLineOption -Colors @{
                Command          = '#5fafff'
                Parameter        = '#87afff'
                Operator         = '#d7d7d7'
                Variable         = '#ffd75f'
                String           = '#87d787'
                Number           = '#ffaf5f'
                Type             = '#5fd7d7'
                Comment          = '#6c6c6c'
                Keyword          = '#ff87d7'
                Error            = '#ff5f5f'
                InlinePrediction = '#5f5f5f'
                ListPrediction   = '#5fafff'
                Selection        = "$([char]27)[48;5;238m"
            }
        } catch {}
    }
}

# -----------------------------------------------------------------------------
# 5. $PSStyle (PS 7+)
# -----------------------------------------------------------------------------
if ($Script:IsPS7 -and (Get-Variable PSStyle -ErrorAction SilentlyContinue)) {
    try {
        $PSStyle.Progress.UseOSCIndicator = $true
        $PSStyle.OutputRendering          = 'Host'
    } catch {}
}

# -----------------------------------------------------------------------------
# 6. ARGUMENT COMPLETERS (only when the tool is present)
# -----------------------------------------------------------------------------
# winget
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding =
            [System.Text.Utf8Encoding]::new()
        $word = $wordToComplete.Replace('"','""')
        $ast  = $commandAst.ToString().Replace('"','""')
        winget complete --word="$word" --commandline "$ast" --position $cursorPosition |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_, $_, 'ParameterValue', $_)
            }
    }
}

# dotnet
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)
        dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_)
        }
    }
}

# gh / kubectl / docker / az: each `<tool> completion <shell>` invocation spawns
# a child process to generate KB of completion script. On Windows that's 200-
# 800ms per tool, cold. Cache the generated script to ~/.gus/completions/<tool>.ps1
# and regenerate only when the tool's binary is newer than the cache.

$Script:GUSCompletionsDir = Join-Path "$env:USERPROFILE\.gus" 'completions'
if (-not (Test-Path $Script:GUSCompletionsDir)) {
    try { New-Item -ItemType Directory -Path $Script:GUSCompletionsDir -Force -ErrorAction Stop | Out-Null }
    catch { $Script:GUSCompletionsDir = $null }
}

function Install-GUSCompletionCache {
    param(
        [Parameter(Mandatory)] [string]$Tool,
        [Parameter(Mandatory)] [string[]]$ArgList,
        [switch]$ForceRefresh
    )
    if (-not $Script:GUSCompletionsDir) { return }
    $cmd = Get-Command $Tool -ErrorAction SilentlyContinue
    if (-not $cmd) { return }

    $cache = Join-Path $Script:GUSCompletionsDir "$Tool.ps1"
    $regen = $ForceRefresh
    if (-not $regen) {
        if (-not (Test-Path $cache)) { $regen = $true }
        else {
            try {
                $cacheTime = (Get-Item $cache).LastWriteTimeUtc
                $toolTime  = (Get-Item $cmd.Source).LastWriteTimeUtc
                if ($toolTime -gt $cacheTime) { $regen = $true }
            } catch { $regen = $true }
        }
    }
    if ($regen) {
        try {
            $out = & $Tool @ArgList 2>$null | Out-String
            if ($out -and $out.Trim().Length -gt 0) {
                Set-Content -Path $cache -Value $out -Encoding utf8 -Force
            }
        } catch {}
    }
    if (Test-Path $cache) {
        try { . $cache } catch { Write-Verbose "Failed to source $cache : $_" }
    }
}

# gh (GitHub CLI)
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Install-GUSCompletionCache -Tool 'gh' -ArgList @('completion','-s','powershell')
}

# kubectl
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Install-GUSCompletionCache -Tool 'kubectl' -ArgList @('completion','powershell')
}

# docker (built into recent docker CLI)
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Install-GUSCompletionCache -Tool 'docker' -ArgList @('completion','powershell')
}

# az (Azure CLI) -- uses a Register-ArgumentCompleter wrapper that calls az
# itself per Tab press. No registration-time shell-out; no caching needed.
if (Get-Command az -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName az -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $env:ARGCOMPLETE_USE_TEMPFILES = 1
        $env:_ARGCOMPLETE_STDOUT_FILENAME = [System.IO.Path]::GetTempFileName()
        $env:COMP_LINE  = $commandAst.ToString()
        $env:COMP_POINT = $cursorPosition
        $env:_ARGCOMPLETE = 1
        $env:_ARGCOMPLETE_SUPPRESS_SPACE = 0
        $env:_ARGCOMPLETE_IFS = "`n"
        az 2>&1 | Out-Null
        Get-Content $env:_ARGCOMPLETE_STDOUT_FILENAME |
            Sort-Object | Get-Unique | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_, $_, 'ParameterValue', $_)
            }
        Remove-Item $env:_ARGCOMPLETE_STDOUT_FILENAME -ErrorAction SilentlyContinue
        'COMP_LINE','COMP_POINT','_ARGCOMPLETE','_ARGCOMPLETE_SUPPRESS_SPACE',
        '_ARGCOMPLETE_IFS','_ARGCOMPLETE_STDOUT_FILENAME','ARGCOMPLETE_USE_TEMPFILES' |
            ForEach-Object { Remove-Item "env:$_" -ErrorAction SilentlyContinue }
    }
}

# -----------------------------------------------------------------------------
# 7. ALIASES & HELPER FUNCTIONS
# -----------------------------------------------------------------------------

# Locate a command (resolves aliases, functions, cmdlets, applications)
function which { param([Parameter(Mandatory)][string]$Name)
    Get-Command $Name -All -ErrorAction SilentlyContinue |
        Select-Object Name, CommandType, Source, Version
}

# touch -- create empty file or update timestamp
function touch { param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) { (Get-Item $Path).LastWriteTime = Get-Date }
    else { New-Item -ItemType File -Path $Path | Out-Null }
}

# mkcd -- mkdir and cd into it
function mkcd { param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

# `..` and `...` for going up
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# History helper with timings
function gh-recent {
    Get-History | Select-Object Id, @{n='Duration';e={
        '{0:n2}s' -f ($_.EndExecutionTime - $_.StartExecutionTime).TotalSeconds
    }}, CommandLine | Format-Table -AutoSize
}

# sudo -- re-launch elevated. Mirrors *nix muscle memory.
# Note: real gsudo (https://github.com/gerardog/gsudo) is better if installed;
# this is the fallback.
function sudo {
    param([Parameter(ValueFromRemainingArguments=$true)] $Arguments)
    if (Get-Command gsudo.exe -ErrorAction SilentlyContinue) {
        & gsudo.exe @Arguments
        return
    }
    $exe = if ($Script:IsPS7) { 'pwsh.exe' } else { 'powershell.exe' }
    if (-not $Arguments -or $Arguments.Count -eq 0) {
        Start-Process $exe -Verb RunAs
    } else {
        $cmd = ($Arguments | ForEach-Object { $_ }) -join ' '
        Start-Process $exe -ArgumentList '-NoExit','-Command',$cmd -Verb RunAs
    }
}

# Profile management
function edit-profile {
    $target = if (Test-Path Variable:GUS_SHARED_PROFILE) {
        $Global:GUS_SHARED_PROFILE
    } else {
        Join-Path "$env:USERPROFILE\.gus" 'GUS.Profile.ps1'
    }
    $editor = if ($env:EDITOR) { $env:EDITOR }
              elseif (Get-Command code -ErrorAction SilentlyContinue) { 'code' }
              elseif (Get-Command notepad++ -ErrorAction SilentlyContinue) { 'notepad++' }
              else { 'notepad' }
    & $editor $target
}

function reload-profile { . $PROFILE.CurrentUserAllHosts }

# Status: what's loaded right now
function gus-status {
    Write-Host ""
    Write-Host "  GUS Profile Status" -ForegroundColor White
    Write-Host "  ------------------" -ForegroundColor DarkGray
    Write-Host ("  PowerShell        : {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
    Write-Host ("  Host              : {0}" -f $Host.Name)
    Write-Host ("  Profile load time : {0} ms" -f $(if ($Script:GUSLoadMs) { $Script:GUSLoadMs } else { 'unknown' }))
    Write-Host ("  Console encoding  : {0}" -f [Console]::OutputEncoding.WebName)
    Write-Host ("  `$OutputEncoding    : {0}" -f $OutputEncoding.WebName)
    Write-Host ("  ProgressPreference: {0}" -f $ProgressPreference)
    Write-Host ("  PSReadLine        : {0}" -f (Get-Module PSReadLine).Version)
    if (Get-Module PSReadLine) {
        $o = Get-PSReadLineOption
        Write-Host ("    Predictions     : {0} ({1})" -f $o.PredictionSource, $o.PredictionViewStyle)
        Write-Host ("    EditMode        : {0}" -f $o.EditMode)
        Write-Host ("    HistoryCount    : {0}" -f $o.MaximumHistoryCount)
    }
    Write-Host ("  Terminal-Icons    : {0}" -f $(if (Get-Module Terminal-Icons) { 'loaded' } else { 'not loaded' }))
    Write-Host ("  posh-git          : {0}" -f $(if (Get-Module posh-git) { 'loaded' } else { 'not loaded' }))
    Write-Host ("  oh-my-posh        : {0}" -f $(if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) { 'available' } else { 'not installed' }))
    Write-Host ""
}

# -----------------------------------------------------------------------------
# 8. OPTIONAL MODULES (load only if installed; don't fail if missing)
# -----------------------------------------------------------------------------
if (Get-Module -ListAvailable Terminal-Icons) {
    try { Import-Module Terminal-Icons -ErrorAction Stop } catch {}
}
if (Get-Module -ListAvailable posh-git) {
    try { Import-Module posh-git -ErrorAction Stop } catch {}
}

# -----------------------------------------------------------------------------
# 9. OH MY POSH INTEGRATION
# -----------------------------------------------------------------------------
# Replaced at install time by Invoke-GUS.ps1 if -IncludeOhMyPosh was passed.
# Otherwise stays as an inert marker so the file remains valid.
#__GUS_OHMYPOSH__

# -----------------------------------------------------------------------------
# 10. PROMPT
# -----------------------------------------------------------------------------
# Replaced entirely by oh-my-posh if loaded. Otherwise: a fast, readable,
# admin-aware prompt with exit code, posh-git branch (when loaded), and
# tilde-collapsed home path.

if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue) -or -not $env:POSH_THEMES_PATH) {
    function prompt {
        $exit = $LASTEXITCODE
        $ok   = $?
        # The cast [WindowsPrincipal][WindowsIdentity]::GetCurrent() must be on
        # ONE line. Split across lines, PS parses [WindowsPrincipal] as a
        # complete type expression and chokes on the next [ even inside parens.
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal       = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
        $isAdmin         = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

        $esc   = [char]27
        $reset = "$esc[0m"
        $dim   = "$esc[38;5;244m"
        $blue  = "$esc[38;5;75m"
        $green = "$esc[38;5;114m"
        $red   = "$esc[38;5;203m"
        $yel   = "$esc[38;5;221m"

        $adminTag = if ($isAdmin) { "${red}#${reset} " } else { '' }
        $exitTag  = if (-not $ok -and $exit) { "${red}[$exit]${reset} " } else { '' }
        $path     = $ExecutionContext.SessionState.Path.CurrentLocation.Path
        $short    = $path -replace [regex]::Escape($HOME),'~'

        $git = ''
        if (Get-Module posh-git) {
            try {
                # Get-GitStatus returns a status object with no side effects.
                # DO NOT use & $GitPromptScriptBlock - that's posh-git's ENTIRE
                # prompt function, which Write-Hosts its own path+git status as
                # a side effect (causing a doubled prompt).
                $status = Get-GitStatus -ErrorAction SilentlyContinue
                if ($status) {
                    $branch = $status.Branch
                    $work   = if ($status.Working) { $status.Working.Length } else { 0 }
                    $idx    = if ($status.Index)   { $status.Index.Length }   else { 0 }
                    $bits   = @()
                    if (($work + $idx) -gt 0) { $bits += "*$($work + $idx)" }
                    if ($status.AheadBy -gt 0)  { $bits += "+$($status.AheadBy)" }
                    if ($status.BehindBy -gt 0) { $bits += "-$($status.BehindBy)" }
                    $extra  = if ($bits.Count) { ' ' + ($bits -join ' ') } else { '' }
                    $git    = " ${yel}[${branch}${extra}]${reset}"
                }
            } catch {}
        }

        # Newline before each prompt for breathing room (skip the very first one)
        $nl = if ($Script:GUSPromptShown) { "`n" } else { '' }
        $Script:GUSPromptShown = $true

        "${nl}${adminTag}${exitTag}${blue}${short}${reset}${git}${green}>${reset} "
    }
}

# -----------------------------------------------------------------------------
# 11. WELCOME BANNER (silent unless interactive)
# -----------------------------------------------------------------------------
# Only show when running interactively in a console host. Skip in scripted
# pipelines, ISE, integrated VS Code (set $env:VSCODE_INJECTION).
if (-not $Script:InISE -and [Environment]::UserInteractive -and -not $env:CI -and -not $env:VSCODE_INJECTION) {
    $Script:GUSLoadStart.Stop()
    $Script:GUSLoadMs = [int]$Script:GUSLoadStart.Elapsed.TotalMilliseconds
    $banner = "GUS loaded in ${Script:GUSLoadMs}ms. Try: gus-status | edit-profile | reload-profile | gus-perf"
    Write-Host "  $banner" -ForegroundColor DarkGray
} else {
    $Script:GUSLoadStart.Stop()
    $Script:GUSLoadMs = [int]$Script:GUSLoadStart.Elapsed.TotalMilliseconds
}

# -----------------------------------------------------------------------------
# 12. PERFORMANCE DIAGNOSTICS
# -----------------------------------------------------------------------------
# gus-perf re-loads the profile in a fresh PowerShell process and measures
# section-by-section timing using a probe injected before each section.
# Use when profile load feels slow (anything > 500ms is worth investigating).
function gus-perf {
    [CmdletBinding()]
    param()

    $profilePath = Join-Path "$env:USERPROFILE\.gus" 'GUS.Profile.ps1'
    if (-not (Test-Path $profilePath)) {
        Write-Host "GUS profile not found at $profilePath" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  GUS profile load timing breakdown" -ForegroundColor White
    Write-Host "  ---------------------------------" -ForegroundColor DarkGray

    # Parse section headers from the profile and time each block.
    $text = Get-Content $profilePath -Raw
    # Each numbered section starts with: # N. <NAME> followed by ---- line
    $sectionRegex = '(?ms)^# (\d+\. [A-Z][^\r\n]+)\r?\n# -+\r?\n(.*?)(?=^# \d+\.|\Z)'
    $matches = [regex]::Matches($text, $sectionRegex)

    if ($matches.Count -eq 0) {
        Write-Host "  Could not parse profile sections; falling back to total load time:" -ForegroundColor Yellow
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        . $profilePath
        $sw.Stop()
        Write-Host ("    Total: {0:n0} ms" -f $sw.Elapsed.TotalMilliseconds)
        return
    }

    $total = 0.0
    foreach ($m in $matches) {
        $name = $m.Groups[1].Value
        $code = $m.Groups[2].Value
        $sb   = [scriptblock]::Create($code)
        $sw   = [System.Diagnostics.Stopwatch]::StartNew()
        try { & $sb } catch { }
        $sw.Stop()
        $ms = $sw.Elapsed.TotalMilliseconds
        $total += $ms
        $color = if ($ms -gt 500) { 'Red' } elseif ($ms -gt 200) { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,8:n0} ms  {1}" -f $ms, $name) -ForegroundColor $color
    }
    Write-Host ("  --------") -ForegroundColor DarkGray
    Write-Host ("  {0,8:n0} ms  TOTAL (sections only; module auto-loads not included)" -f $total) -ForegroundColor White
    Write-Host ""
    Write-Host "  Refresh completion caches with: Install-GUSCompletionCache -Tool gh -ArgList completion,-s,powershell -ForceRefresh" -ForegroundColor DarkGray
}

# Force-refresh all completion caches
function gus-refresh-completions {
    foreach ($t in @(
        @{ Tool='gh';      ArgList=@('completion','-s','powershell') }
        @{ Tool='kubectl'; ArgList=@('completion','powershell') }
        @{ Tool='docker';  ArgList=@('completion','powershell') }
    )) {
        if (Get-Command $t.Tool -ErrorAction SilentlyContinue) {
            Write-Host "Refreshing $($t.Tool) completion cache..." -ForegroundColor Cyan
            Install-GUSCompletionCache -Tool $t.Tool -ArgList $t.ArgList -ForceRefresh
        }
    }
}
