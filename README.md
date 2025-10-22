# avd-diagnostics-collector

# Collect-AVDUpdateLogs.ps1

Collect **Windows Update**, **servicing**, and **Azure Virtual Desktop (AVD)** agent diagnostics into a single ZIP file for support/triage.

## What it collects

- **Core Servicing**
  - `C:\Windows\Logs\CBS\CBS.log` and `CbsPersist_*.log`
  - `C:\Windows\Logs\DISM\dism.log`
  - `C:\Windows\WinSxS\pending.xml` (if present)
- **Windows Update**
  - `C:\Windows\SoftwareDistribution\ReportingEvents.log`
  - ETL traces from `C:\Windows\Logs\WindowsUpdate\*.etl`
  - Merged `WindowsUpdate.log` (via `Get-WindowsUpdateLog`)
- **Event Logs (.evtx)**
  - `System`, `Application`
  - `Microsoft-Windows-WindowsUpdateClient/Operational`
  - `Microsoft-Windows-Servicing/Operational`
  - `Setup` (if present)
- **Environment Snapshot**
  - `systeminfo` output
  - Installed updates list (`Get-HotFix`)
  - `DISM /Online /Cleanup-Image /CheckHealth` output
- **Azure VM Agent Logs**
  - `C:\WindowsAzure\Logs\WaAppAgent.log`
  - `C:\WindowsAzure\Logs\Plugins\`
- **AVD Agent Logs**
  - `C:\ProgramData\Microsoft\RDInfra\`
  - `C:\ProgramData\Microsoft\RDAgent\`
- **Intune/MDM (optional)**
  - `MDMDiagnostics.cab` (via `mdmdiagnosticstool.exe`)

>  The script is **read-only** and **does not modify** the system.

## Requirements

- Windows 10/11 or Windows Server 2019/2022 (AVD session host or personal host)
- PowerShell 5.1+
- Run **as Administrator**
- Free disk space: **~500 MB+** recommended (depending on log sizes)
- Execution policy that allows the script to run (see usage)

## Usage

1. Download the script.
2. Open **PowerShell as Administrator**.
3. (Optional) Allow running scripts for this session:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   ```
4. Run the script:
   ```powershell
   .\Collect-AVDUpdateLogs.ps1
   ```
5. The output ZIP will be created at:
   ```
   C:\Temp\AVD_UpdateDiag_<yyyyMMdd_HHmmss>.zip
   ```

## Parameters

- `-OutputRoot "C:\SomeFolder"`  
  Change the parent folder for the working directory and ZIP. Default: `C:\Temp`.

- `-SkipWindowsUpdateLog`  
  Skip generating the merged `WindowsUpdate.log` (still copies ETLs). Useful if merging is slow or Windows Update service is disabled.

- `-SkipMDMDiagnostics`  
  Skip collecting the `MDMDiagnostics.cab` with `mdmdiagnosticstool.exe`.

- `-Quiet`  
  Reduce console output (still writes a `collector.log` into the working folder).

### Examples

Collect with defaults:
```powershell
.\Collect-AVDUpdateLogs.ps1
```

Change output folder and skip the merged WindowsUpdate.log:
```powershell
.\Collect-AVDUpdateLogs.ps1 -OutputRoot D:\Diag -SkipWindowsUpdateLog
```

Minimal output and no MDM diagnostics:
```powershell
.\Collect-AVDUpdateLogs.ps1 -Quiet -SkipMDMDiagnostics
```

## Output

- A working folder: `C:\Temp\AVD_UpdateDiag_<timestamp>\`
- A packaged ZIP: `C:\Temp\AVD_UpdateDiag_<timestamp>.zip`
- A `README.txt` and a `collector.log` inside the working folder describing contents and actions taken.

## Notes & Troubleshooting

- **Get-WindowsUpdateLog fails**: If the Windows Update ETL traces aren’t present or the service is disabled, the merge may fail. The script logs the error and continues.
- **Event log export errors**: Some channels (e.g., `Setup`) may not exist on all hosts. The script will continue and note it in `collector.log`.
- **Large ZIP**: The Azure `Plugins` and AVD agent folders can be large. If size is a concern, zip the folder yourself after removing older subfolders.

## License

MIT (adjust as needed for your repo).
