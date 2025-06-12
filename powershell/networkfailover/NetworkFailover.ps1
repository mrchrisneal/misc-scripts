# Win 11 Network Failover Script
# Version 1.2 by mrchrisneal - March 13th, 2025

# IMPORTANT UPDATE:
# As of June 11th, 2025, the current iteration of this script does not work as expected 
# after extensive testing. If you'd like to use and improve this script yourself, please 
# feel free to do so. Hopefully someone will find this useful! Thank you!

# IMPORTANT: This script requires additional configuration!
# Please refer to the README located on GitHub for further information:
# https://github.com/mrchrisneal/misc-scripts/tree/main/powershell/networkfailover

#region Script Parameters 
# -------- BEGIN USER CONFIG --------
param (
    # The interface description of your primary network adapter
    [string]$PrimaryAdapterDescription = "Wireless Network Adapter", 
    
    # The interface description of your iPhone USB connection
    [string]$BackupAdapterDescription = "Apple Mobile Device Ethernet", 
    
    # How many consecutive ping failures before switching to backup
    [int]$FailureThreshold = 4, 
    
    # How many seconds to wait between connectivity checks
    [int]$CheckInterval = 1, 
    
    # How many seconds to wait after primary connection recovers before switching back
    [int]$RestoreDelay = 5,
    
    # Test hosts - IPv4 and IPv6 addresses (no DNS resolution needed)
    [string[]]$TestHosts = @("8.8.8.8", "2001:4860:4860::8888"),
    
    # Enable verbose debug output
    [switch]$Debug = $false
)
#endregion 
# -------- END USER CONFIG --------

#region Administrator Check
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Please restart with elevated privileges."
    exit 1
}
#endregion

#region Helper Functions
# Function to write debug messages
function Write-DebugMessage {
    param (
        [string]$Message
    )
    
    if ($Debug) {
        Write-Host "[DEBUG] $Message" -ForegroundColor Cyan
    }
}

# Improved function to test internet through a specific adapter
function Test-InternetViaAdapter {
    param (
        [string]$AdapterName,
        [string[]]$Hosts = $TestHosts,
        [int]$TimeoutMs = 500  # Fast timeout
    )
    
    Write-DebugMessage "Testing connectivity via adapter '$AdapterName'..."
    
    # Get the adapter's interface index
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-DebugMessage "Adapter '$AdapterName' not found"
        return $false
    }
    
    if ($adapter.Status -ne "Up") {
        Write-DebugMessage "Adapter '$AdapterName' is not up"
        return $false
    }
    
    # Get the IPv4 address for this adapter
    $ipv4 = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $ipv4) {
        Write-DebugMessage "No IPv4 address found for adapter '$AdapterName'"
        return $false
    }
    
    Write-DebugMessage "Using source IP address $($ipv4.IPAddress) for tests"
    
    # Get PowerShell version to handle different Test-Connection parameter sets
    $psVersion = $PSVersionTable.PSVersion.Major
    
    # Test connectivity to each host
    foreach ($testHost in $Hosts) {
        try {
            Write-DebugMessage "Pinging $testHost from adapter '$AdapterName'..."
            
            if ($psVersion -ge 6) {
                # PowerShell 6+ syntax
                $result = Test-Connection -TargetName $testHost -Count 1 -Source $ipv4.IPAddress -TimeoutSeconds 1 -ErrorAction Stop
            } else {
                # PowerShell 5.1 and earlier syntax
                $result = Test-Connection -ComputerName $testHost -Count 1 -Source $ipv4.IPAddress -ErrorAction Stop
            }
            
            if ($result) {
                Write-DebugMessage "Successfully pinged $testHost via '$AdapterName'"
                return $true
            }
        } 
        catch {
            Write-DebugMessage "Ping to $testHost via '$AdapterName' failed: $($_.Exception.Message)"
        }
    }
    
    Write-DebugMessage "All connectivity tests failed for adapter '$AdapterName'"
    return $false
}

# Legacy function for general connectivity test (any route)
function Test-Internet {
    foreach ($testHost in $TestHosts) {
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $result = $ping.Send($testHost, 2000)
            if ($result.Status -eq "Success") {
                return $true
            }
        } catch {
            # Continue to next host on error
        }
    }
    return $false
}

# Function to find a network adapter by its interface description
function Get-AdapterByDescription {
    param (
        $Description
    )
    
    $adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*$Description*" } | Select-Object -First 1
    return $adapter
}

# Function to show IP addresses for an adapter
function Show-AdapterAddresses {
    param (
        $AdapterName
    )
    
    $addresses = Get-NetIPAddress -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue
    $ipv4 = ($addresses | Where-Object { $_.AddressFamily -eq "IPv4" }).IPAddress -join ", "
    $ipv6 = ($addresses | Where-Object { $_.AddressFamily -eq "IPv6" }).IPAddress -join ", "
    
    if (-not $ipv4) { $ipv4 = "None" }
    if (-not $ipv6) { $ipv6 = "None" }
    
    return "IPv4: $ipv4, IPv6: $ipv6"
}
#endregion

#region Adapter Setup
# Find adapters
$primary = Get-AdapterByDescription -Description $PrimaryAdapterDescription
$backup = Get-AdapterByDescription -Description $BackupAdapterDescription

# Verify both adapters exist
if (-not $primary) {
    Write-Error "Primary adapter with description containing '$PrimaryAdapterDescription' not found. Available adapters:"
    Get-NetAdapter | Format-Table Name, InterfaceDescription
    exit 1
}

if (-not $backup) {
    Write-Error "Backup adapter with description containing '$BackupAdapterDescription' not found. Available adapters:"
    Get-NetAdapter | Format-Table Name, InterfaceDescription
    exit 1
}

# Display adapter information
Write-Host "Using primary adapter: $($primary.Name) ($($primary.InterfaceDescription))"
Write-Host "Primary adapter addresses: $(Show-AdapterAddresses -AdapterName $primary.Name)"
Write-Host "Using backup adapter: $($backup.Name) ($($backup.InterfaceDescription))"
Write-Host "Backup adapter addresses: $(Show-AdapterAddresses -AdapterName $backup.Name)"
#endregion

#region Initial Setup
# Track state
$usingBackup = $false
$failureCount = 0

# Ensure backup adapter is initially disabled
if ($backup.Status -eq "Up") {
    Write-Host "Disabling backup adapter to start..."
    try {
        Disable-NetAdapter -Name $backup.Name -Confirm:$false
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "Warning: Failed to disable backup adapter: $($_.Exception.Message)"
    }
}

# Ensure primary adapter is enabled
if ($primary.Status -ne "Up") {
    Write-Host "Enabling primary adapter to start..."
    try {
        Enable-NetAdapter -Name $primary.Name -Confirm:$false
        Start-Sleep -Seconds 5
    } catch {
        Write-Host "Warning: Failed to enable primary adapter: $($_.Exception.Message)"
    }
}

Write-Host "Starting network failover monitor..."
Write-Host "Press Ctrl+C to exit"
#endregion

#region Main Loop
try {
    while ($true) {
        $startTime = Get-Date
        
        # Test internet connectivity (fast parallel test)
        $connected = Test-Internet
        
        $endTime = Get-Date
        $testDuration = ($endTime - $startTime).TotalMilliseconds
        Write-DebugMessage "Connection test took $testDuration ms"
        
        if (-not $connected) {
            # Handle connection failure
            $failureCount++
            Write-Host "Connection failure detected ($failureCount/$FailureThreshold)"
            
            # If this is the first failure, test again immediately to confirm
            if ($failureCount -eq 1) {
                Write-DebugMessage "Confirming failure with immediate retest..."
                Start-Sleep -Milliseconds 100
                $doubleCheck = Test-Internet
                if ($doubleCheck) {
                    Write-Host "False alarm - connection is working on retest"
                    $failureCount = 0
                }
            }
            
            if (($failureCount -ge $FailureThreshold) -and (-not $usingBackup)) {
                Write-Host "Switching to backup connection..."
                
                # Enable backup adapter
                try {
                    Enable-NetAdapter -Name $backup.Name -Confirm:$false
                    Write-DebugMessage "Waiting for backup adapter to initialize..."
                    # Wait for adapter to initialize, but check it every 500ms
                    $maxWait = 10  # Maximum 5 seconds (10 x 500ms)
                    $waited = 0
                    while (($waited -lt $maxWait) -and 
                           ((Get-NetAdapter -Name $backup.Name).Status -ne "Up" -or 
                            -not (Get-NetIPAddress -InterfaceAlias $backup.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue))) {
                        Start-Sleep -Milliseconds 500
                        $waited++
                        Write-DebugMessage "Waiting for backup adapter... ($waited/$maxWait)"
                    }
                } catch {
                    Write-Host "Error enabling backup adapter: $($_.Exception.Message)"
                }
                
                # Set routing metrics
                try {
                    Set-NetIPInterface -InterfaceAlias $backup.Name -InterfaceMetric 1
                    Set-NetIPInterface -InterfaceAlias $primary.Name -InterfaceMetric 9999
                } catch {
                    Write-Host "Error setting interface metrics: $($_.Exception.Message)"
                }
                
                $usingBackup = $true
                Write-Host "Now using backup connection"
                
                # Test if backup is working
                Start-Sleep -Seconds 2
                if (Test-Internet) {
                    Write-Host "Backup connection is working"
                } else {
                    Write-Host "Warning: Backup connection doesn't seem to be working either"
                }
            }
        }
        else {
            # Reset failure counter
            $failureCount = 0
            
            # If on backup but primary might be working again, test primary
            if ($usingBackup) {
                Write-Host "Testing if primary connection is restored..."
                
                # First check if primary adapter is actually up
                $primaryStatus = Get-NetAdapter -Name $primary.Name | Select-Object -ExpandProperty Status
                if ($primaryStatus -ne "Up") {
                    Write-Host "Primary adapter is not up (status: $primaryStatus), staying on backup"
                    Start-Sleep -Seconds $CheckInterval
                    continue
                }
                
                # Check if primary adapter has a valid IP address
                $primaryIP = Get-NetIPAddress -InterfaceAlias $primary.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
                if (-not $primaryIP) {
                    Write-Host "Primary adapter doesn't have a valid IPv4 address, staying on backup"
                    Start-Sleep -Seconds $CheckInterval
                    continue
                }
                
                Write-Host "Primary adapter is up with IP $($primaryIP.IPAddress), testing connectivity..."
                
                # Test specifically through the primary adapter
                $primaryWorking = Test-InternetViaAdapter -AdapterName $primary.Name
                
                if ($primaryWorking) {
                    Write-Host "Primary connection is working. Waiting $RestoreDelay seconds before switching back..."
                    Start-Sleep -Seconds $RestoreDelay
                    
                    # Test again to ensure stability
                    $stillWorking = Test-InternetViaAdapter -AdapterName $primary.Name
                    if ($stillWorking) {
                        Write-Host "Switching back to primary connection..."
                        
                        # Reset metrics to prefer primary
                        try {
                            Set-NetIPInterface -InterfaceAlias $primary.Name -InterfaceMetric 1
                            Set-NetIPInterface -InterfaceAlias $backup.Name -InterfaceMetric 9999
                        } catch {
                            Write-Host "Error setting metrics: $($_.Exception.Message)"
                        }
                        
                        # Give routing time to update
                        Start-Sleep -Seconds 2
                        
                        # Disable backup to save power
                        try {
                            Disable-NetAdapter -Name $backup.Name -Confirm:$false
                        } catch {
                            Write-Host "Warning: Failed to disable backup adapter: $($_.Exception.Message)"
                        }
                        
                        $usingBackup = $false
                        Write-Host "Now using primary connection"
                    } else {
                        Write-Host "Primary connection became unstable, staying on backup"
                    }
                } else {
                    Write-Host "Primary connection still not working, staying on backup"
                }
            }
        }
        
        # Wait before next check
        Start-Sleep -Seconds $CheckInterval
    }
}
finally {
    # Cleanup on exit
    if ($usingBackup) {
        Write-Host "Restoring network settings..."
        try {
            Set-NetIPInterface -InterfaceAlias $primary.Name -InterfaceMetric 1
        } catch {
            # Suppress cleanup errors
        }
    }
    Write-Host "Script terminated"
}
#endregion
