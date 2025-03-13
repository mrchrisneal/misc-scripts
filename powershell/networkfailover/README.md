# Network Failover Script User Guide

## Overview

The NetworkFailover.ps1 script automatically switches between your primary internet connection and a backup connection when your main connection fails. When your primary connection goes down, the script enables your mobile device's USB hotspot and switches back when the main connection returns.

## Prerequisites

- Windows 11 operating system
- PowerShell
- Administrator privileges
- Mobile device with USB tethering capability
- Both network adapters must be present in your system

## Setup Instructions

### Step 1: Identify Your Network Adapters

Before configuring the script, you need to identify the exact names of your network adapters:

1. Open PowerShell as Administrator
2. Run the following command:
   ```
   Get-NetAdapter | Format-Table Name, InterfaceDescription
   ```
3. Note the `InterfaceDescription` values for both your:
   - Primary network adapter (e.g., "Intel(R) Wi-Fi 6 AX201 160MHz")
   - Backup/mobile device adapter (e.g., "Apple Mobile Device Ethernet")

### Step 2: Configure the Script

Open the NetworkFailover.ps1 script in a text editor and modify the following parameters:

1. `$PrimaryAdapterDescription` - Set this to match your primary network adapter description
2. `$BackupAdapterDescription` - Set this to match your mobile device adapter description

Optional configuration parameters:
- `$FailureThreshold` - Number of consecutive ping failures before switching (default: 4)
- `$CheckInterval` - Seconds between connectivity checks (default: 1)
- `$RestoreDelay` - Seconds to wait before switching back to primary (default: 5)
- `$TestHosts` - IP addresses to test connectivity against

### Step 3: Save the Script

Save the script in a permanent location such as:
```
C:\Tools\NetworkFailover.ps1
```

## Running the Script

### Manual Execution

1. Connect your mobile device via USB
2. Open PowerShell as Administrator
3. Navigate to the script location:
   ```
   cd C:\Tools
   ```
4. Run the script:
   ```
   .\NetworkFailover.ps1
   ```

For detailed troubleshooting information, add the `-Debug` flag:
```
.\NetworkFailover.ps1 -Debug
```

### Automatic Startup (Not Recommended)

To make the script run automatically at system startup:

1. Open Task Scheduler
2. Create a new task:
   - Run with highest privileges
   - Trigger: At system startup
   - Action: Start a program
   - Program: powershell.exe
   - Arguments: `-ExecutionPolicy Bypass -File "C:\Tools\NetworkFailover.ps1"`

## Troubleshooting

### Execution Policy Errors

If you receive an error about execution policy, use one of these solutions:

- Temporary solution (safest):
  ```
  powershell -ExecutionPolicy Bypass -File "C:\Tools\NetworkFailover.ps1"
  ```

- User-level solution:
  ```
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```

- System-wide solution:
  ```
  Set-ExecutionPolicy -Scope LocalMachine RemoteSigned
  ```

### Adapter Not Found

If the script can't find your adapters:

1. Run the command to see available adapters:
   ```
   Get-NetAdapter | Format-Table Name, InterfaceDescription
   ```
2. Update the script parameters to match your exact adapter descriptions

### USB Device Not Connected

The mobile device must be connected via USB before starting the script. Make sure:
- The phone is connected before running the script
- USB tethering is enabled on your device
- You're using a data cable (not just a charging cable)

## Important Notes

- The script must run with Administrator privileges
- Your mobile device must be connected via USB when the script starts
- The script continuously monitors your internet connection
- To stop the script, press Ctrl+C in the PowerShell window