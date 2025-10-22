<#
.SYNOPSIS
  Collects Windows Update, servicing, and AVD agent diagnostics into a single ZIP file.

.DESCRIPTION
  Gathers logs from:
   - Core servicing (CBS, DISM, pending.xml)
   - Windows Update (ETLs, merged WindowsUpdate.log)
   - Event logs (.evtx)
   - Environment snapshot (systeminfo, installed updates, DISM /CheckHealth)
   - Azure VM Agent logs
   - AVD Agent logs (RDInfra and RDAgent)
   - Intune / MDM diagnostics (optional)

.NOTES
  Run as Administrator. Read-only: does not modify system state.
#>

[CmdletBinding()]
param(
  [string]$OutputRoot = "C:\Temp",
  [switch]$SkipWindowsUpdateLog,
  [switch]$SkipMDMDiagnostics,
  [switch]$Quiet
)

# Require admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Run this script in an elevated PowerShell session (Run as Administrator)."
  exit 1
}

$ErrorActionPreference = 'Continue'
$ts   = Get-Date -Format "yyyyMMdd_HHmmss"
$work = Join-Path $OutputRoot "AVD_UpdateDiag_$ts"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# Logging helpers
$logFile = Join-Path $work "collector.log"
function Log {
  param([string]$Message)
  if (-not $Quiet) { Write-Host $Message }
  Add-Content -Path $logFile -Value ("[{0}] {1}" -f (Get-Date), $Message)
}
function Ensure-Dir {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}
function SafeCopy {
  param([string]$Path, [string]$DestFolder)
  try {
    # Support wildcards in $Path
    $items = Get-Item -Path $Path -ErrorAction SilentlyContinue -Force
    if ($null -ne $items) {
      Ensure-Dir -Path $DestFolder
      Copy-Item -Path $Path -Destination $DestFolder -Recurse -Force -ErrorAction Stop
      Log "Copied: $Path"
    } else {
      Log "Not found: $Path"
    }
  } catch {
    Log "Failed to copy '$Path' -> '$DestFolder' : $($_.Exception.Message)"
  }
}

Log "Starting AVD diagnostics collection in $work"

# --- Core servicing ---
SafeCopy "C:\Windows\Logs\CBS\CBS.log" $work
SafeCopy "C:\Windows\Logs\CBS\CbsPersist_*.log" $work
SafeCopy "C:\Windows\Logs\DISM\dism.log" $work
SafeCopy "C:\Windows\WinSxS\pending.xml" $work

# --- Windows Update ---
SafeCopy "C:\Windows\SoftwareDistribution\ReportingEvents.log" $work
$wuEtlDest = Join-Path $work "WindowsUpdateETL"
Ensure-Dir $wuEtlDest
SafeCopy "C:\Windows\Logs\WindowsUpdate\*.etl" $wuEtlDest

if (-not $SkipWindowsUpdateLog) {
  try {
    $merged = Join-Path $work "WindowsUpdate.log"
    Log "Generating merged WindowsUpdate.log (may take a minute)..."
    Get-WindowsUpdateLog -LogPath $merged -Force
    Log "Merged WindowsUpdate.log created at: $merged"
  } catch {
    Log "Get-WindowsUpdateLog failed: $($_.Exception.Message)"
  }
} else {
  Log "Skipping merged WindowsUpdate.log per parameter."
}

# --- Event logs (.evtx) ---
$evtx = @(
  "System",
  "Application",
  "Microsoft-Windows-WindowsUpdateClient/Operational",
  "Microsoft-Windows-Servicing/Operational",
  "Setup"
)
foreach ($log in $evtx) {
  $safeName = $log -replace '[\\/]', '-'
  $outPath = Join-Path $work "$safeName.evtx"
  try {
    wevtutil epl "$log" "$outPath"
    Log "Exported event log: $log"
  } catch {
    Log "Failed to export event log '$log' : $($_.Exception.Message)"
  }
}

# --- Environment snapshot ---
try {
  systeminfo | Out-File -FilePath (Join-Path $work "systeminfo.txt") -Encoding UTF8
  Log "Captured systeminfo."
} catch { Log "systeminfo failed: $($_.Exception.Message)" }

try {
  Get-HotFix |
    Sort-Object InstalledOn |
    Select-Object HotFixID, Description, InstalledOn, InstalledBy |
    Format-Table -AutoSize | Out-String |
    Out-File (Join-Path $work "hotfixes.txt")
  Log "Captured installed updates (Get-HotFix)."
} catch { Log "Get-HotFix failed: $($_.Exception.Message)" }

try {
  Log "Running DISM /Online /Cleanup-Image /CheckHealth (read-only)..."
  dism /Online /Cleanup-Image /CheckHealth | Out-File (Join-Path $work "dism_checkhealth_output.txt")
  Log "Captured DISM CheckHealth output."
} catch { Log "DISM CheckHealth failed: $($_.Exception.Message)" }

# --- Azure VM Agent logs ---
SafeCopy "C:\WindowsAzure\Logs\WaAppAgent.log" $work
SafeCopy "C:\WindowsAzure\Logs\Plugins" (Join-Path $work "AzurePlugins")

# --- AVD Agent logs ---
SafeCopy "C:\ProgramData\Microsoft\RDInfra" (Join-Path $work "AVDAgent_RDInfra")
SafeCopy "C:\ProgramData\Microsoft\RDAgent" (Join-Path $work "AVDAgent_RDAgent")

# --- Intune / MDM diagnostics (optional) ---
if (-not $SkipMDMDiagnostics) {
  $mdmCab = Join-Path $work "MDMDiagnostics.cab"
  try {
    $areas = "Autopilot;DeviceEnrollment;DeviceProvisioning;WindowsUpdate"
    Log "Running mdmdiagnosticstool.exe (areas: $areas)..."
    Start-Process -FilePath "mdmdiagnosticstool.exe" -ArgumentList "-area $areas -cab `"$mdmCab`"" -Wait -WindowStyle Hidden
    if (Test-Path $mdmCab) {
      Log "MDMDiagnostics.cab created."
    } else {
      Log "MDMDiagnosticsTool completed but CAB not found."
    }
  } catch {
    Log "MDMDiagnosticsTool not available or failed: $($_.Exception.Message)"
  }
} else {
  Log "Skipping MDMDiagnostics per parameter."
}

# --- README manifest ---
$readme = @"
AVD Windows Update / Servicing diagnostics
==========================================
Created: $(Get-Date -Format o)
Host: $env:COMPUTERNAME
Folder: $work

Contents:
- CBS.log, CbsPersist_*.log
- dism.log
- pending.xml (if present)
- ReportingEvents.log
- WindowsUpdate ETL files
- WindowsUpdate.log (merged, if generated)
- Event logs: System, Application, WindowsUpdateClient-Operational, Servicing-Operational, Setup
- systeminfo.txt, hotfixes.txt, dism_checkhealth_output.txt
- Azure VM Agent logs (if present)
- AVD Agent logs (RDInfra, RDAgent)
- MDMDiagnostics.cab (if generated)

This package is read-only; it does not modify the system.
"@
$readme | Out-File -FilePath (Join-Path $work "README.txt") -Encoding UTF8

# --- Zip it ---
$zipPath = "$work.zip"
try {
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path $work -DestinationPath $zipPath -Force
  Log "Packaged logs: $zipPath"
} catch {
  Log "Compress-Archive failed: $($_.Exception.Message)"
}

Log "Done."
Write-Host "`n Logs collected: $zipPath"
