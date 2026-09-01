<#
.SYNOPSIS
  Debloat script for Windows 11 / Windows Server based on tiny11builder concepts.
.DESCRIPTION
  This script removes unnecessary AppxPackages, disables telemetry, disables reserved storage,
  and optimizes services for a minimal Vagrant box footprint.
#>

Write-Host "Starting Windows Debloat Process..." -ForegroundColor Cyan

# Disable Reserved Storage to reclaim ~7 GB
try {
    Write-Host "Disabling Reserved Storage..." -ForegroundColor Yellow
    DISM.exe /Online /Set-ReservedStorageState /State:Disabled
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ShippedWithReserves" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "PassedPolicy" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "WARN: Could not disable reserved storage: $_"
}

# Remove unnecessary Appx and Provisioned packages
$packagesToRemove = @(
    "Clipchamp.Clipchamp",
    "Microsoft.549981C3F5F10",
    "Microsoft.BingNews",
    "Microsoft.BingSearch",
    "Microsoft.BingWeather",
    "Microsoft.Copilot",
    "Microsoft.DesktopAppInstaller",
    "Microsoft.GamingApp",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.Messaging",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.MixedReality.Portal",
    "Microsoft.NetworkSpeedTest",
    "Microsoft.News",
    "Microsoft.Office.OneNote",
    "Microsoft.OneConnect",
    "Microsoft.OneDriveSync",
    "Microsoft.OutlookForWindows",
    "Microsoft.Paint3D",
    "Microsoft.People",
    "Microsoft.PowerAutomateDesktop",
    "Microsoft.Print3D",
    "Microsoft.ScreenSketch",
    "Microsoft.SkypeApp",
    "Microsoft.StorePurchaseApp",
    "Microsoft.Todos",
    "Microsoft.Wallet",
    "Microsoft.Windows.Ai.Copilot.Provider",
    "Microsoft.Windows.DevHome",
    "Microsoft.WindowsAlarms",
    "Microsoft.WindowsCamera",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsSoundRecorder",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.YourPhone",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "MicrosoftCorporationII.MicrosoftFamily",
    "MicrosoftCorporationII.QuickAssist",
    "MicrosoftTeams",
    "MSTeams",
    "microsoft.windowscommunicationsapps"
)

Write-Host "Removing Appx Packages..." -ForegroundColor Yellow
foreach ($package in $packagesToRemove) {
    Get-AppxPackage -Name $package -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $package -or $_.PackageName -like "*$package*" } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# Disable Telemetry and Diagnostics
Write-Host "Disabling Telemetry and Diagnostics..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Disable Crash Dumps
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "CrashDumpEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Disable Telemetry, Search Indexing, and Background Services
$servicesToDisable = @(
    "DiagTrack",        # Connected User Experiences and Telemetry
    "dmwappushservice", # WAP Push Message Routing Service
    "SysMain",          # Superfetch / SysMain
    "WSearch",          # Windows Search Indexer
    "MapsBroker",       # Downloaded Maps Manager
    "WerSvc",           # Windows Error Reporting
    "RetailDemo",       # Retail Demo Service
    "DoSvc",            # Delivery Optimization
    "XblAuthManager",   # Xbox Live Auth Manager
    "XblGameSave",      # Xbox Live Game Save
    "XboxNetApiSvc"     # Xbox Live Networking Service
)

Write-Host "Disabling Unnecessary Services..." -ForegroundColor Yellow
foreach ($service in $servicesToDisable) {
    Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
}

# Remove OneDrive if present
Write-Host "Attempting to remove OneDrive..." -ForegroundColor Yellow
if (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
    Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait -NoNewWindow
} elseif (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") {
    Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait -NoNewWindow
}

# Remove Microsoft Edge and WebView2 aggressively
Write-Host "Attempting to remove Microsoft Edge and WebView2..." -ForegroundColor Yellow
try {
    $edgeSetup = (Get-ChildItem -Path "C:\Program Files (x86)\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($edgeSetup) {
        Write-Host "Uninstalling Edge..."
        Start-Process -FilePath $edgeSetup.FullName -ArgumentList "--uninstall --system-level --verbose-logging --force-uninstall" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }
    
    $webviewSetup = (Get-ChildItem -Path "C:\Program Files (x86)\Microsoft\EdgeWebView\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($webviewSetup) {
        Write-Host "Uninstalling Edge WebView2..."
        Start-Process -FilePath $webviewSetup.FullName -ArgumentList "--uninstall --msedgewebview --system-level --verbose-logging --force-uninstall" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }

    # Force delete leftovers
    Remove-Item -Path "C:\Program Files (x86)\Microsoft\Edge*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Path "C:\Program Files\Microsoft\Edge*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
} catch {
    Write-Host "WARN: Could not completely remove Edge: $_"
}

Write-Host "Debloat complete." -ForegroundColor Green
