<#
.SYNOPSIS
  Debloat script for Windows Server 2025 based on tiny11builder concepts.
.DESCRIPTION
  This script removes unnecessary AppxPackages, disables telemetry, and optimizes
  services for a minimal Vagrant box footprint.
#>

Write-Host "Starting Windows Server Debloat Process..." -ForegroundColor Cyan

# Remove unnecessary Appx packages
$packagesToRemove = @(
    "Microsoft.BingWeather",
    "Microsoft.DesktopAppInstaller",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.Messaging",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.NetworkSpeedTest",
    "Microsoft.News",
    "Microsoft.Office.OneNote",
    "Microsoft.OneConnect",
    "Microsoft.Paint3D",
    "Microsoft.People",
    "Microsoft.Print3D",
    "Microsoft.SkypeApp",
    "Microsoft.StorePurchaseApp",
    "Microsoft.Todos",
    "Microsoft.Wallet",
    "Microsoft.WindowsAlarms",
    "Microsoft.WindowsCamera",
    "microsoft.windowscommunicationsapps",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsSoundRecorder",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo"
)

Write-Host "Removing Appx Packages..." -ForegroundColor Yellow
foreach ($package in $packagesToRemove) {
    Get-AppxPackage -Name $package -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $package | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# Disable Telemetry and Data Collection
Write-Host "Disabling Telemetry and Diagnostics..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Disable Telemetry Services
$servicesToDisable = @(
    "DiagTrack", # Connected User Experiences and Telemetry
    "dmwappushservice", # WAP Push Message Routing Service
    "SysMain" # Superfetch / SysMain (often unneeded on VMs backed by SSDs)
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

Write-Host "Debloat complete." -ForegroundColor Green
