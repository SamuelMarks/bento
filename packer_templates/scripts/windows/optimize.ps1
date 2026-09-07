Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function Write-SerialLog {
    param([string]$message)
    Write-Host $message
    try {
        cmd.exe /c "echo [WIN11-OPTIMIZE] $message > COM1" 2>$null
    } catch { }
}

trap {
    Write-Host
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split "`r`n") -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split "`r`n") -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Write-Host
    Exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Write-SerialLog "Starting Windows 11 Disk Optimization & Size Reduction..."

Write-SerialLog "Enabling CompactOS filesystem compression on system binaries..."
try {
    compact.exe /compactOS:always
} catch {
    Write-SerialLog "CompactOS warning: $_"
}

Write-SerialLog "Compressing static program and system directories using LZX..."
@(
    "C:\Program Files",
    "C:\Program Files (x86)",
    "C:\Windows\System32\DriverStore\FileRepository",
    "C:\Windows\System32\WindowsPowerShell",
    "C:\Windows\Microsoft.NET",
    "C:\Windows\Inf",
    "C:\Windows\Fonts",
    "C:\Windows\WinSxS"
) | ForEach-Object {
    if (Test-Path $_) {
        try {
            compact.exe /c /s /a /i /exe:lzx "$_\*" 2>$null
        } catch { }
    }
}

Write-SerialLog "Disabling Hibernation to remove hiberfil.sys..."
try {
    powercfg.exe /hibernate off
} catch { }

Write-SerialLog "Deleting Volume Shadow Copies..."
try {
    vssadmin.exe delete shadows /all /quiet 2>$null
} catch { }

Write-SerialLog "Disabling System Restore..."
try {
    Disable-ComputerRestore -Drive "C:" -ErrorAction SilentlyContinue
} catch { }

Write-SerialLog "Purging Recycle Bin and DNS cache..."
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Clear-DnsClientCache -ErrorAction SilentlyContinue
} catch { }

Write-SerialLog "Defragmenting and consolidating volume free space..."
try {
    Optimize-Volume -DriveLetter C -Defrag -Verbose
} catch {
    Write-SerialLog "Defrag warning: $_"
}

Write-SerialLog "Zeroing free disk space for maximum box compression..."
$FilePath = "C:\zero.tmp"
$ArraySize = 4MB
$ZeroArray = [byte[]]::new($ArraySize)

try {
    $Stream = [System.IO.File]::OpenWrite($FilePath)
    try {
        while ($true) {
            $Stream.Write($ZeroArray, 0, $ZeroArray.Length)
        }
    } catch {
        # Disk full reached - expected
        Write-SerialLog "Free disk space successfully saturated with zeroes."
    } finally {
        if ($Stream) {
            try { $Stream.Close() } catch { }
            try { $Stream.Dispose() } catch { }
            $Stream = $null
        }
    }
} catch {
    Write-SerialLog "Zeroing completed: $_"
} finally {
    $ZeroArray = $null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 2
    if (Test-Path $FilePath) {
        Remove-Item -Force $FilePath -ErrorAction SilentlyContinue
    }
}

Write-SerialLog "ReTrimming Drive to unmap zeroed free blocks at hypervisor level..."
try {
    Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction SilentlyContinue
} catch {
    Write-SerialLog "ReTrim warning: $_"
}

Write-SerialLog "Disk optimization, zero-wipe, and ReTrim complete."
exit 0
