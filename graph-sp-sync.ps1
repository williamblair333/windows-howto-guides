#Requires -Version 7.4
<#
.SYNOPSIS
    SharePoint Online document library comparison and sync tool via Microsoft Graph API.

.DESCRIPTION
    Universal utility for comparing and synchronizing SharePoint Online document libraries.
    No external modules required — pure PowerShell 7.4+ and Microsoft Graph REST API.

    Three modes of operation:
      Count — Fast recursive file count comparison (lightweight, no path collection).
      Diff  — Full path enumeration, outputs CSV of files missing from destination.
      Copy  — Diff + copies missing files from source to destination.

    Auth: Authorization code flow with PKCE (browser popup, localhost:8400 redirect).
    Works with tenants that have Security Defaults enabled (no device code flow needed).

    Prerequisites:
      - Entra app registration with delegated permissions:
          Count/Diff: Sites.Read.All
          Copy:       Sites.ReadWrite.All
      - "Allow public client flows" enabled on the app registration
      - http://localhost:8400 registered as a Mobile/Desktop redirect URI

.PARAMETER Tenant
    SharePoint tenant name (the part before .sharepoint.com). Required.

.PARAMETER TenantId
    Entra tenant identifier for auth. Defaults to <Tenant>.onmicrosoft.com.
    Override if your Entra tenant name differs from your SharePoint tenant name,
    or pass your actual Entra tenant GUID.

.PARAMETER SourceSite
    Source site path, e.g. "sites/Finance". Required.

.PARAMETER SourceFolder
    Folder within the source Documents library, e.g. "Reports/2024".
    Omit to target the entire library root.

.PARAMETER DestSite
    Destination site path, e.g. "sites/FinanceArchive". Required.

.PARAMETER DestFolder
    Folder within the destination Documents library.
    Omit to target the entire library root.

.PARAMETER ClientId
    Entra app registration client ID. Falls back to ConfigFile if not specified.

.PARAMETER ConfigFile
    Path to a Key=Value text file containing ClientId=<guid>.
    Defaults to .\graph-sync-config.txt.

.PARAMETER Mode
    "Count" = fast file count comparison (no path collection).
    "Diff"  = enumerate paths, report missing files to CSV.
    "Copy"  = diff + copy missing files to destination.
    Default: Count

.PARAMETER ReportPath
    Path to write the diff/copy report CSV (Diff and Copy modes).
    Default: .\missing-files-report.csv

.EXAMPLE
    # Quick count comparison
    .\graph-sp-sync.ps1 `
        -Tenant contoso `
        -ClientId "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" `
        -SourceSite sites/OldSite `
        -SourceFolder "Archive" `
        -DestSite sites/NewSite `
        -DestFolder "Archive" `
        -Mode Count

.EXAMPLE
    # Find missing files — outputs CSV report
    .\graph-sp-sync.ps1 `
        -Tenant contoso `
        -SourceSite sites/OldSite `
        -SourceFolder "Archive" `
        -DestSite sites/NewSite `
        -Mode Diff

.EXAMPLE
    # Copy missing files to destination
    .\graph-sp-sync.ps1 `
        -Tenant contoso `
        -SourceSite sites/OldSite `
        -SourceFolder "Archive" `
        -DestSite sites/NewSite `
        -Mode Copy

.EXAMPLE
    # TenantId override (vanity domain doesn't match .onmicrosoft.com)
    .\graph-sp-sync.ps1 `
        -Tenant fabrikam `
        -TenantId "a1b2c3d4-5678-9abc-def0-123456789abc" `
        -SourceSite sites/HR `
        -DestSite sites/HRArchive `
        -Mode Diff

.EXAMPLE
    # Use config file for ClientId
    .\graph-sp-sync.ps1 `
        -Tenant contoso `
        -ConfigFile .\my-app-config.txt `
        -SourceSite sites/Legal `
        -DestSite sites/LegalArchive `
        -Mode Copy

.EXAMPLE
    # Compare entire document libraries (no subfolder)
    .\graph-sp-sync.ps1 `
        -Tenant contoso `
        -SourceSite sites/Marketing `
        -DestSite sites/MarketingBackup `
        -Mode Count

.NOTES
    For large-scale or recurring sync operations, consider rclone (https://rclone.org)
    which supports SharePoint via Microsoft Graph and offers parallel transfers,
    incremental sync, and a GUI (RcloneView). This script is best suited for
    environments where installing external tools is not an option, or for quick
    one-off validation.

    Config file format (Key=Value, one per line):
        ClientId=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee

.LINK
    https://learn.microsoft.com/en-us/graph/api/resources/onedrive
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Tenant,

    [string]$TenantId     = "",

    [Parameter(Mandatory)]
    [string]$SourceSite,

    [string]$SourceFolder = "",

    [Parameter(Mandatory)]
    [string]$DestSite,

    [string]$DestFolder   = "",
    [string]$ClientId     = "",
    [string]$ConfigFile   = ".\graph-sync-config.txt",

    [ValidateSet("Count","Diff","Copy")]
    [string]$Mode         = "Count",

    [string]$ReportPath   = ".\missing-files-report.csv"
)

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════
$GraphBase      = "https://graph.microsoft.com/v1.0"
$SharePointHost = "$Tenant.sharepoint.com"

if (-not $TenantId) {
    $TenantId = "$Tenant.onmicrosoft.com"
}

# Resolve client ID: explicit param > config file
if (-not $ClientId) {
    if (Test-Path $ConfigFile) {
        $configContent = Get-Content $ConfigFile -Raw
        if ($configContent -match 'ClientId\s*=\s*(.+)') {
            $ClientId = $Matches[1].Trim()
            Write-Host "[config] Loaded ClientId from $ConfigFile"
        }
    }
}
if (-not $ClientId) {
    Write-Host "ERROR: No ClientId provided." -ForegroundColor Red
    Write-Host "  Pass -ClientId <guid> or create a config file with ClientId=<guid>" -ForegroundColor Red
    Write-Host "  Default config file path: $ConfigFile" -ForegroundColor DarkGray
    exit 1
}

# Normalize empty folder strings to null
if ([string]::IsNullOrWhiteSpace($SourceFolder)) { $SourceFolder = $null }
if ([string]::IsNullOrWhiteSpace($DestFolder))   { $DestFolder   = $null }

# Auth scope: ReadWrite only needed for Copy
$graphScope = if ($Mode -eq "Copy") {
    "https://graph.microsoft.com/Sites.ReadWrite.All offline_access"
} else {
    "https://graph.microsoft.com/Sites.Read.All offline_access"
}

# ══════════════════════════════════════════════════════════════════════════════
# SHARED FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════
Add-Type -AssemblyName System.Web

# ── Auth: Authorization Code Flow with PKCE ───────────────────────────────────
function Get-GraphToken {
    param(
        [string]$ClientId,
        [string]$TenantId,
        [string]$Scope
    )

    $redirectUri  = "http://localhost:8400"
    $tokenUrl     = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $authorizeUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize"

    # PKCE code verifier and challenge
    $verifierBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($verifierBytes)
    $codeVerifier = [Convert]::ToBase64String($verifierBytes) -replace '\+','-' -replace '/','_' -replace '='
    $challengeBytes = [System.Security.Cryptography.SHA256]::HashData(
        [System.Text.Encoding]::ASCII.GetBytes($codeVerifier)
    )
    $codeChallenge = [Convert]::ToBase64String($challengeBytes) -replace '\+','-' -replace '/','_' -replace '='

    # CSRF state
    $stateBytes = [byte[]]::new(16)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($stateBytes)
    $state = [Convert]::ToBase64String($stateBytes) -replace '\+','-' -replace '/','_' -replace '='

    $authParams = @(
        "client_id=$ClientId"
        "response_type=code"
        "redirect_uri=$([uri]::EscapeDataString($redirectUri))"
        "scope=$([uri]::EscapeDataString($Scope))"
        "code_challenge=$codeChallenge"
        "code_challenge_method=S256"
        "state=$state"
    )
    $fullAuthUrl = "$authorizeUrl`?$($authParams -join '&')"

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("$redirectUri/")
    $listener.Start()

    Write-Host ""
    Write-Host "=== SIGN IN REQUIRED ===" -ForegroundColor Yellow
    Write-Host "Opening browser for sign-in..."
    Write-Host "If the browser does not open, go to:" -ForegroundColor DarkGray
    Write-Host $fullAuthUrl -ForegroundColor DarkGray
    Write-Host ""

    Start-Process $fullAuthUrl

    # Wait for redirect (120 second timeout)
    $asyncResult = $listener.BeginGetContext($null, $null)
    $waitResult  = $asyncResult.AsyncWaitHandle.WaitOne(120000)

    if (-not $waitResult) {
        $listener.Stop()
        throw "Sign-in timed out after 120 seconds. Re-run the script."
    }

    $context  = $listener.EndGetContext($asyncResult)
    $request  = $context.Request
    $response = $context.Response

    $html = [System.Text.Encoding]::UTF8.GetBytes(
        "<html><body><h2>Sign-in complete</h2><p>You can close this tab.</p></body></html>"
    )
    $response.ContentType = "text/html"
    $response.ContentLength64 = $html.Length
    $response.OutputStream.Write($html, 0, $html.Length)
    $response.Close()
    $listener.Stop()

    $queryParams   = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
    $returnedState = $queryParams["state"]
    $authCode      = $queryParams["code"]
    $authError     = $queryParams["error"]

    if ($authError) {
        throw "Auth failed: $authError - $($queryParams["error_description"])"
    }
    if ($returnedState -ne $state) {
        throw "Auth failed: state mismatch (possible CSRF). Re-run the script."
    }
    if (-not $authCode) {
        throw "Auth failed: no authorization code received."
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body @{
        client_id     = $ClientId
        grant_type    = "authorization_code"
        code          = $authCode
        redirect_uri  = $redirectUri
        code_verifier = $codeVerifier
    }

    Write-Host "[auth] Token acquired." -ForegroundColor Green
    return $tokenResponse.access_token
}

# ── Graph REST helper with throttle retry ─────────────────────────────────────
function Invoke-Graph {
    param(
        [string]$Uri,
        [string]$Token,
        [string]$Method      = "GET",
        [object]$Body,
        [string]$ContentType,
        [int]$MaxRetries     = 5
    )

    $headers = @{ Authorization = "Bearer $Token" }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $params = @{
                Uri         = $Uri
                Method      = $Method
                Headers     = $headers
                ErrorAction = "Stop"
            }
            if ($Body -and $Method -ne "GET") {
                $params.Body = $Body
                if ($ContentType) { $params.ContentType = $ContentType }
            }
            return Invoke-RestMethod @params
        }
        catch {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -eq 429 -or $status -eq 503 -or $status -eq 504) {
                $wait = [math]::Max(5, [math]::Pow(2, $attempt))
                try {
                    $retryAfter = $_.Exception.Response.Headers.GetValues("Retry-After")[0]
                    if ($retryAfter) { $wait = [math]::Max([int]$retryAfter, $wait) }
                } catch {}
                Write-Warning "Throttled ($status). Retry $attempt/$MaxRetries in ${wait}s..."
                Start-Sleep -Seconds $wait
            }
            else {
                $detail = $_.ErrorDetails.Message
                Write-Host "[graph] ERROR $status on $Uri" -ForegroundColor Red
                if ($detail) {
                    $parsed = $detail | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($parsed.error.message) {
                        Write-Host "        $($parsed.error.message)" -ForegroundColor Red
                    }
                }
                return $null
            }
        }
    }
    Write-Host "[graph] Failed after $MaxRetries retries on $Uri" -ForegroundColor Red
    return $null
}

# ── Site and drive resolution ─────────────────────────────────────────────────
function Get-SiteId {
    param(
        [string]$SPHost,
        [string]$SitePath,
        [string]$Token
    )
    $uri  = "$GraphBase/sites/${SPHost}:/${SitePath}"
    $site = Invoke-Graph -Uri $uri -Token $Token
    if (-not $site) { throw "Could not resolve site: $SitePath" }
    Write-Host "[site]  $($site.displayName) -> $($site.id)"
    return $site.id
}

function Get-DocumentsDriveId {
    param(
        [string]$SiteId,
        [string]$Token
    )
    $uri    = "$GraphBase/sites/$SiteId/drives"
    $drives = Invoke-Graph -Uri $uri -Token $Token
    if (-not $drives) { throw "Could not list drives for site $SiteId" }

    $docDrive = $drives.value |
        Where-Object { $_.name -eq "Documents" -or $_.name -eq "Shared Documents" } |
        Select-Object -First 1
    if (-not $docDrive) {
        Write-Host "[drive] Available drives:" -ForegroundColor Yellow
        $drives.value | ForEach-Object { Write-Host "        - $($_.name) ($($_.id))" }
        throw "No 'Documents' drive found."
    }
    Write-Host "[drive] $($docDrive.name) -> $($docDrive.id)"
    return $docDrive.id
}

# ── Path encoding helper ─────────────────────────────────────────────────────
function Get-EncodedPath {
    param([string]$Path)
    return ($Path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
}

# ══════════════════════════════════════════════════════════════════════════════
# COUNT MODE — lightweight recursive file counter (no path collection)
# ══════════════════════════════════════════════════════════════════════════════
function Get-FileCountRecursive {
    param(
        [string]$DriveId,
        [string]$FolderPath,
        [string]$Token
    )

    if ($FolderPath) {
        $encodedPath = Get-EncodedPath $FolderPath
        $baseUri = "$GraphBase/drives/$DriveId/root:/${encodedPath}:/children"
    }
    else {
        $baseUri = "$GraphBase/drives/$DriveId/root/children"
    }

    $fileCount   = 0
    $folderCount = 0
    $uri = "${baseUri}?`$top=200&`$select=id,name,folder,file"

    while ($uri) {
        $batch = Invoke-Graph -Uri $uri -Token $Token
        if (-not $batch) {
            Write-Host "[warn] Failed to enumerate: $uri" -ForegroundColor Yellow
            return -1
        }

        foreach ($item in $batch.value) {
            if ($null -ne $item.file) {
                $fileCount++
            }
            elseif ($null -ne $item.folder) {
                $folderCount++
                $subPath = if ($FolderPath) { "$FolderPath/$($item.name)" } else { $item.name }
                $subCount = Get-FileCountRecursive -DriveId $DriveId -FolderPath $subPath -Token $Token
                if ($subCount -ge 0) { $fileCount += $subCount }
            }
        }

        $uri = $batch.'@odata.nextLink'
    }

    if ($folderCount -gt 0) {
        $label = if ($FolderPath) { $FolderPath.Split('/')[-1] } else { '(root)' }
        Write-Host "[scan] ../$label : $fileCount files, $folderCount subfolders" -ForegroundColor DarkGray
    }

    return $fileCount
}

# ══════════════════════════════════════════════════════════════════════════════
# DIFF/COPY MODE — full path enumeration
# ══════════════════════════════════════════════════════════════════════════════
function Get-AllFiles {
    param(
        [string]$DriveId,
        [string]$FolderPath,
        [string]$RootPrefix,
        [string]$Token,
        [string]$Label
    )

    $files = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($FolderPath) {
        $encodedPath = Get-EncodedPath $FolderPath
        $baseUri = "$GraphBase/drives/$DriveId/root:/${encodedPath}:/children"
    }
    else {
        $baseUri = "$GraphBase/drives/$DriveId/root/children"
    }

    $uri = "${baseUri}?`$top=200&`$select=id,name,folder,file,size,lastModifiedDateTime"

    while ($uri) {
        $batch = Invoke-Graph -Uri $uri -Token $Token
        if (-not $batch) {
            Write-Host "[warn] Failed to enumerate: $uri" -ForegroundColor Yellow
            break
        }

        foreach ($item in $batch.value) {
            if ($null -ne $item.file) {
                $fullPath = if ($FolderPath) { "$FolderPath/$($item.name)" } else { $item.name }

                $relativePath = if ($RootPrefix -and $fullPath.StartsWith("$RootPrefix/")) {
                    $fullPath.Substring($RootPrefix.Length + 1)
                }
                else {
                    $fullPath
                }

                $files.Add([PSCustomObject]@{
                    RelativePath = $relativePath
                    FullPath     = $fullPath
                    Name         = $item.name
                    Size         = $item.size
                    LastModified = $item.lastModifiedDateTime
                    Id           = $item.id
                })
            }
            elseif ($null -ne $item.folder) {
                $subPath  = if ($FolderPath) { "$FolderPath/$($item.name)" } else { $item.name }
                $subFiles = Get-AllFiles -DriveId $DriveId -FolderPath $subPath -RootPrefix $RootPrefix -Token $Token -Label $Label
                foreach ($sf in $subFiles) {
                    $files.Add($sf)
                }
            }
        }

        $uri = $batch.'@odata.nextLink'
    }

    if (-not $FolderPath -or $FolderPath -eq $RootPrefix) {
        Write-Host "[$Label] Total: $($files.Count) files" -ForegroundColor Green
    }
    elseif ($files.Count -gt 0) {
        $folderName = $FolderPath.Split('/')[-1]
        Write-Host "[$Label] ../$folderName : $($files.Count) files" -ForegroundColor DarkGray
    }

    return ,$files
}

# ── File copy: download from source, upload to destination ────────────────────
function Copy-FileToDestination {
    param(
        [string]$DriveId,
        [string]$ItemId,
        [string]$DestDriveId,
        [string]$DestFolderPath,
        [string]$RelativePath,
        [long]$FileSize,
        [string]$Token
    )

    # Get fresh download URL (they expire within minutes)
    $itemData = Invoke-Graph -Uri "$GraphBase/drives/$DriveId/items/$ItemId" -Token $Token
    if (-not $itemData) { throw "Could not fetch source item metadata" }

    $downloadUrl = $itemData.'@microsoft.graph.downloadUrl'
    if (-not $downloadUrl) { throw "No download URL available" }

    # Download file content
    $fileResponse = Invoke-WebRequest -Uri $downloadUrl -Method GET
    $content      = $fileResponse.Content

    # Build encoded destination path
    $destRelative = if ($DestFolderPath) { "$DestFolderPath/$RelativePath" } else { $RelativePath }
    $encodedDest  = Get-EncodedPath $destRelative

    if ($FileSize -lt 4194304) {
        # Simple upload (< 4 MB)
        $uploadUri = "$GraphBase/drives/$DestDriveId/root:/${encodedDest}:/content"
        Invoke-RestMethod -Uri $uploadUri -Method PUT -Body $content `
                          -ContentType "application/octet-stream" `
                          -Headers @{ Authorization = "Bearer $Token" } | Out-Null
    }
    else {
        # Resumable upload session (>= 4 MB)
        $sessionUri  = "$GraphBase/drives/$DestDriveId/root:/${encodedDest}:/createUploadSession"
        $sessionBody = @{
            item = @{
                "@microsoft.graph.conflictBehavior" = "rename"
            }
        } | ConvertTo-Json

        $session   = Invoke-RestMethod -Uri $sessionUri -Method POST -Body $sessionBody `
                                       -ContentType "application/json" `
                                       -Headers @{ Authorization = "Bearer $Token" }
        $uploadUrl = $session.uploadUrl
        $chunkSize = 10 * 1024 * 1024  # 10 MB chunks
        $totalSize = $content.Length
        $position  = 0

        while ($position -lt $totalSize) {
            $end   = [math]::Min($position + $chunkSize - 1, $totalSize - 1)
            $chunk = $content[$position..$end]
            $contentRange = "bytes $position-$end/$totalSize"

            Invoke-RestMethod -Uri $uploadUrl -Method PUT -Body ([byte[]]$chunk) `
                              -ContentType "application/octet-stream" `
                              -Headers @{ "Content-Range" = $contentRange } | Out-Null

            $position = $end + 1
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference = "Stop"
$startTime = Get-Date

$sourceLabel = if ($SourceFolder) { "/$SourceSite/Documents/$SourceFolder" } else { "/$SourceSite/Documents/ (full library)" }
$destLabel   = if ($DestFolder)   { "/$DestSite/Documents/$DestFolder" }     else { "/$DestSite/Documents/ (full library)" }

Write-Host ""
Write-Host "SharePoint Graph Sync Tool" -ForegroundColor Cyan
Write-Host "Mode:   $Mode" -ForegroundColor Cyan
Write-Host "Source: $sourceLabel"
Write-Host "Dest:   $destLabel"

# ── Authenticate ──────────────────────────────────────────────────────────────
$token = Get-GraphToken -ClientId $ClientId -TenantId $TenantId -Scope $graphScope

# ── Resolve source ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- SOURCE ---" -ForegroundColor Cyan
$sourceSiteId  = Get-SiteId -SPHost $SharePointHost -SitePath $SourceSite -Token $token
$sourceDriveId = Get-DocumentsDriveId -SiteId $sourceSiteId -Token $token

# ── Resolve destination ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- DESTINATION ---" -ForegroundColor Cyan
$destSiteId  = Get-SiteId -SPHost $SharePointHost -SitePath $DestSite -Token $token
$destDriveId = Get-DocumentsDriveId -SiteId $destSiteId -Token $token

# ══════════════════════════════════════════════════════════════════════════════
# COUNT MODE
# ══════════════════════════════════════════════════════════════════════════════
if ($Mode -eq "Count") {
    Write-Host ""
    Write-Host "[count] Counting source $(if ($SourceFolder) { "/$SourceFolder" } else { '/Documents root' }) (recursive)..."
    $sourceCount = Get-FileCountRecursive -DriveId $sourceDriveId -FolderPath $SourceFolder -Token $token

    Write-Host ""
    Write-Host "[count] Counting dest $(if ($DestFolder) { "/$DestFolder" } else { '/Documents root' }) (recursive)..."
    $destCount = Get-FileCountRecursive -DriveId $destDriveId -FolderPath $DestFolder -Token $token

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  RESULTS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Source: $sourceLabel -- $sourceCount files"
    Write-Host "  Dest:   $destLabel -- $destCount files"
    Write-Host ""

    if ($sourceCount -ge 0 -and $destCount -ge 0) {
        $diff = $sourceCount - $destCount
        if ($diff -eq 0) {
            Write-Host "  MATCH - File counts are equal." -ForegroundColor Green
        }
        elseif ($diff -gt 0) {
            Write-Host "  MISMATCH - Source has $diff MORE files than destination." -ForegroundColor Yellow
        }
        else {
            Write-Host "  MISMATCH - Destination has $([math]::Abs($diff)) MORE files than source." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  Could not compare - one or both counts failed." -ForegroundColor Red
    }

    Write-Host "========================================"
}

# ══════════════════════════════════════════════════════════════════════════════
# DIFF / COPY MODE
# ══════════════════════════════════════════════════════════════════════════════
if ($Mode -eq "Diff" -or $Mode -eq "Copy") {

    Write-Host ""
    Write-Host "[enum] Enumerating source $(if ($SourceFolder) { "/$SourceFolder" } else { 'root' }) (recursive)..."
    $srcFiles = Get-AllFiles -DriveId $sourceDriveId -FolderPath $SourceFolder -RootPrefix $SourceFolder -Token $token -Label "SRC"

    Write-Host ""
    Write-Host "[enum] Enumerating dest $(if ($DestFolder) { "/$DestFolder" } else { 'root' }) (recursive)..."
    $destFiles = Get-AllFiles -DriveId $destDriveId -FolderPath $DestFolder -RootPrefix $DestFolder -Token $token -Label "DEST"

    # ── Build diff ────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "--- COMPARISON ---" -ForegroundColor Cyan

    $destLookup = @{}
    foreach ($f in $destFiles) {
        $destLookup[$f.RelativePath.ToLower()] = $true
    }

    $missing = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($f in $srcFiles) {
        if (-not $destLookup.ContainsKey($f.RelativePath.ToLower())) {
            $missing.Add($f)
        }
    }

    Write-Host "  Source files:      $($srcFiles.Count)"
    Write-Host "  Destination files: $($destFiles.Count)"
    if ($missing.Count -eq 0) {
        Write-Host "  Missing from dest: 0 — MATCH" -ForegroundColor Green
    }
    else {
        Write-Host "  Missing from dest: $($missing.Count)" -ForegroundColor Yellow
    }

    # Write report CSV
    $missing | Select-Object RelativePath, Name, Size, LastModified |
        Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "  Report: $ReportPath" -ForegroundColor Cyan
}

# ══════════════════════════════════════════════════════════════════════════════
# COPY MODE
# ══════════════════════════════════════════════════════════════════════════════
if ($Mode -eq "Copy" -and $missing.Count -gt 0) {
    Write-Host ""
    Write-Host "--- COPYING $($missing.Count) FILES ---" -ForegroundColor Yellow

    $copied = 0
    $failed = 0
    $errors = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($file in $missing) {
        $index = $copied + $failed + 1
        Write-Host "  [$index/$($missing.Count)] $($file.RelativePath)" -ForegroundColor Gray -NoNewline

        try {
            Copy-FileToDestination `
                -DriveId $sourceDriveId `
                -ItemId $file.Id `
                -DestDriveId $destDriveId `
                -DestFolderPath $DestFolder `
                -RelativePath $file.RelativePath `
                -FileSize $file.Size `
                -Token $token

            $copied++
            Write-Host " OK" -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Host " FAIL: $($_.Exception.Message)" -ForegroundColor Red
            $errors.Add([PSCustomObject]@{
                RelativePath = $file.RelativePath
                Error        = $_.Exception.Message
            })
        }
    }

    Write-Host ""
    Write-Host "--- COPY COMPLETE ---" -ForegroundColor Cyan
    Write-Host "  Copied: $copied" -ForegroundColor Green
    if ($failed -gt 0) {
        Write-Host "  Failed: $failed" -ForegroundColor Red
        $errorReport = $ReportPath -replace '\.csv$', '-errors.csv'
        $errors | Export-Csv -Path $errorReport -NoTypeInformation
        Write-Host "  Error report: $errorReport" -ForegroundColor Yellow
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────
$elapsed = (Get-Date) - $startTime
Write-Host ""
Write-Host "Elapsed: $($elapsed.ToString('hh\:mm\:ss'))"
