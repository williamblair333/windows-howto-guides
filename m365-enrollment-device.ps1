<#
.SYNOPSIS
    Interactive device enrollment script for Entra Join + Intune MDM.
    Automates verification steps. Pauses for manual actions that require the UI.
    Run as Administrator.

.EXAMPLE
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; .\enroll-device.ps1
#>

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$ErrorActionPreference = "SilentlyContinue"

function Pause-ForManualStep {
    param([string]$Message)
    Write-Host ""
    Write-Host "  >>> MANUAL STEP REQUIRED <<<" -ForegroundColor Yellow
    Write-Host "  $Message" -ForegroundColor White
    Write-Host ""
    Write-Host "  Press ENTER when done..." -ForegroundColor Gray
    Read-Host
}

function Check-EntraJoin {
    $dsreg = dsregcmd /status 2>&1 | Out-String

    $result = @{
        AzureAdJoined  = $dsreg -match 'AzureAdJoined\s*:\s*YES'
        WorkplaceOnly  = ($dsreg -match 'WorkplaceJoined\s*:\s*YES') -and ($dsreg -notmatch 'AzureAdJoined\s*:\s*YES')
        AzureAdPrt     = $dsreg -match 'AzureAdPrt\s*:\s*YES'
        IsUserAzureAD  = $dsreg -match 'Executing Account Name\s*:\s*AzureAD\\'
        MdmUrlPresent  = $dsreg -match 'MdmUrl\s*:\s*https://'
    }

    return $result
}

function Check-IntuneEnrollment {
    $enrollment = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.ProviderID -eq "MS DM Server" }

    return $enrollment
}

# ===================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEVICE ENROLLMENT - Entra + Intune" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Hostname : $env:COMPUTERNAME"
Write-Host "  Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Write-Host "  User     : $env:USERNAME"
Write-Host ""

# ===================================================================
# STEP 1: Check current state
# ===================================================================
Write-Host "--- Step 1: Checking current join state ---" -ForegroundColor Yellow

$state = Check-EntraJoin

if ($state.AzureAdJoined) {
    Write-Host "  [PASS] Already Entra Joined" -ForegroundColor Green
}
elseif ($state.WorkplaceOnly) {
    Write-Host "  [!!] Workplace Registered only - NOT Entra Joined" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Must remove stale registration before joining." -ForegroundColor White

    Pause-ForManualStep "Go to Settings -> Accounts -> Access work or school -> click existing account -> Disconnect. Then REBOOT. After reboot, run this script again."
    exit 0
}
else {
    Write-Host "  [--] Not joined to anything" -ForegroundColor Gray
    Write-Host ""

    Pause-ForManualStep @"
Perform Entra Join now:
  1. Settings -> Accounts -> Access work or school -> Connect
  2. Click 'Join this device to Microsoft Entra ID'
  3. Enter work email (UPN)
  4. Complete MFA if prompted
  5. When done, SIGN OUT
  6. At login screen, click 'Other user'
  7. Sign in with work email (NOT a local account)
  8. Then run this script again.
"@
    exit 0
}

# ===================================================================
# STEP 2: Verify PRT and user context
# ===================================================================
Write-Host ""
Write-Host "--- Step 2: Checking user context ---" -ForegroundColor Yellow

# Re-check after possible login change
$state = Check-EntraJoin

if ($state.AzureAdPrt) {
    Write-Host "  [PASS] Primary Refresh Token present" -ForegroundColor Green
}
else {
    Write-Host "  [FAIL] No PRT - signed in with local account" -ForegroundColor Red

    Pause-ForManualStep @"
Sign out and sign back in with your WORK EMAIL:
  1. Sign out of Windows
  2. At login screen, click 'Other user'
  3. Sign in with your work email (user@domain.com)
  4. Then run this script again.
"@
    exit 0
}

if ($state.IsUserAzureAD) {
    Write-Host "  [PASS] User is Azure AD identity" -ForegroundColor Green
}
else {
    Write-Host "  [FAIL] User is not Azure AD identity" -ForegroundColor Red

    Pause-ForManualStep "Sign out and sign in with work email, not a local account. Then run this script again."
    exit 0
}

if ($state.MdmUrlPresent) {
    Write-Host "  [PASS] MDM discovery URL present" -ForegroundColor Green
}
else {
    Write-Host "  [WARN] MDM URL not found in dsregcmd output" -ForegroundColor Yellow
}

# ===================================================================
# STEP 3: Check Intune MDM enrollment
# ===================================================================
Write-Host ""
Write-Host "--- Step 3: Checking Intune MDM enrollment ---" -ForegroundColor Yellow

$mdm = Check-IntuneEnrollment

if ($mdm) {
    Write-Host "  [PASS] Intune MDM enrolled" -ForegroundColor Green
    Write-Host "  UPN: $($mdm.UPN)" -ForegroundColor Gray
}
else {
    Write-Host "  [FAIL] No Intune MDM enrollment found" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Attempting to trigger MDM enrollment..." -ForegroundColor Yellow

    Start-Process "ms-device-enrollment:?mode=mdm"

    Pause-ForManualStep @"
The enrollment dialog should have opened.
  1. Enter your work email
  2. If it says 'We couldn't auto-discover a management endpoint'
     enter this URL in the MDM Server URL field:
     https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc
  3. Complete the dialog
  4. Press ENTER here when done
"@

    # Re-check
    Write-Host "  Re-checking enrollment..." -ForegroundColor Gray
    Start-Sleep -Seconds 5

    $mdm = Check-IntuneEnrollment

    if ($mdm) {
        Write-Host "  [PASS] Intune MDM enrolled" -ForegroundColor Green
        Write-Host "  UPN: $($mdm.UPN)" -ForegroundColor Gray
    }
    else {
        Write-Host "  [FAIL] Still not enrolled. Check MDM user scope in portal:" -ForegroundColor Red
        Write-Host "  intune.microsoft.com -> Devices -> Device onboarding -> Enrollment -> Windows tab -> Automatic Enrollment" -ForegroundColor Gray
        Write-Host "  MDM user scope must be All or include this user's group." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Exiting. Fix MDM scope and run script again." -ForegroundColor Red
        exit 1
    }
}

# ===================================================================
# STEP 4: Force Intune sync
# ===================================================================
Write-Host ""
Write-Host "--- Step 4: Forcing Intune policy sync ---" -ForegroundColor Yellow

$mdm = Check-IntuneEnrollment

if ($mdm) {
    $enrollID = Split-Path $mdm.PSPath -Leaf
    $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\$enrollID\" -ErrorAction SilentlyContinue

    if ($tasks) {
        foreach ($task in $tasks) {
            Start-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction SilentlyContinue
        }
        Write-Host "  [OK] Intune sync triggered ($($tasks.Count) tasks)" -ForegroundColor Green
    }
    else {
        Write-Host "  [--] No sync tasks found yet (may take a few minutes to create)" -ForegroundColor Gray
    }
}

# ===================================================================
# STEP 5: Final summary
# ===================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  FINAL VERIFICATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$state = Check-EntraJoin
$mdm = Check-IntuneEnrollment

$allChecks = @(
    @{ Name = "Entra Joined";       Pass = $state.AzureAdJoined },
    @{ Name = "Primary Refresh Token"; Pass = $state.AzureAdPrt },
    @{ Name = "Azure AD User";       Pass = $state.IsUserAzureAD },
    @{ Name = "MDM URL Present";     Pass = $state.MdmUrlPresent },
    @{ Name = "Intune MDM Enrolled"; Pass = ($null -ne $mdm) }
)

$allPassed = $true
foreach ($check in $allChecks) {
    if ($check.Pass) {
        Write-Host "  [PASS] $($check.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "  [FAIL] $($check.Name)" -ForegroundColor Red
        $allPassed = $false
    }
}

Write-Host ""

if ($allPassed) {
    Write-Host "  DEVICE FULLY ENROLLED" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor White
    Write-Host "  1. Check portal: intune.microsoft.com -> Devices -> All devices -> $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host "  2. If ownership shows Personal, change to Corporate in Properties" -ForegroundColor Gray
    Write-Host "  3. Policies will apply within 1-2 hours (or immediately if sync was triggered)" -ForegroundColor Gray
}
else {
    Write-Host "  ENROLLMENT INCOMPLETE - review failures above" -ForegroundColor Red
}

Write-Host ""
