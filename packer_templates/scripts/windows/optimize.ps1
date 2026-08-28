#MIT License
#
#Copyright (c) 2017 Rui Lopes
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

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
