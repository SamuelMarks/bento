Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

trap {
    Write-Host
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '?
') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '?
') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Write-Host
    Exit 1
}

# Enable TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Write-Host "Enabling CompactOS compression on system binaries..."
try {
    compact.exe /compactOS:always
} catch {
    Write-Host "CompactOS warning: $_"
}

Write-Host "Compressing static program directories using LZX..."
@(
    "C:\Program Files",
    "C:\Program Files (x86)",
    "C:\Windows\System32\DriverStore\FileRepository"
) | ForEach-Object {
    if (Test-Path $_) {
        try {
            compact.exe /c /s /a /i /exe:lzx "$_\*" 2>$null
        } catch { }
    }
}

Write-Host "Disabling Hibernation to remove hiberfil.sys..."
try {
    powercfg.exe /hibernate off
} catch { }

Write-Host "Optimizing and defragmenting volume..."
try {
    Optimize-Volume -DriveLetter C -Defrag -Verbose
} catch {
    Write-Host "Defrag warning: $_"
}

Write-Host "Zeroing free disk space for maximum box compression..."
$FilePath = "C:\zero.tmp"
$ArraySize = 4MB
$ZeroArray = [byte[]]::new($ArraySize)

try {
    $Stream = [System.IO.File]::OpenWrite($FilePath)
    try {
        while ($true) {
            $Stream.Write($ZeroArray, 0, $ZeroArray.Length)
        }
    } catch [System.IO.IOException] {
        # Disk full reached - expected
        Write-Host "Free disk space successfully filled with zeroes."
    } finally {
        if ($Stream) {
            $Stream.Flush()
            $Stream.Close()
            $Stream.Dispose()
        }
    }
} catch {
    Write-Host "Zeroing caught error: $_"
} finally {
    if (Test-Path $FilePath) {
        Remove-Item -Force $FilePath -ErrorAction SilentlyContinue
    }
}

Write-Host "ReTrimming Drive to unmap zeroed free blocks at hypervisor level..."
try {
    Optimize-Volume -DriveLetter C -ReTrim -Verbose
} catch {
    Write-Host "ReTrim warning: $_"
}
