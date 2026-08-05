# PowerShell script to package build zip and generate Inno Setup installer for RDPMS Serial Monitor v2.0.0
param (
    [string]$InnoCompiler = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = "Stop"

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " Building RDPMS Serial Monitor Zip & Inno Setup  " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# Directories
$WorkspaceRoot = $PSScriptRoot
$ReleaseBuildDir = Join-Path $WorkspaceRoot "serial_monitor\build\windows\x64\runner\Release"
$OutputDir = Join-Path $WorkspaceRoot "installer_output"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

if (-not (Test-Path $ReleaseBuildDir)) {
    Write-Error "Release build directory not found at $ReleaseBuildDir. Please run 'flutter build windows --release' in serial_monitor directory first."
}

# Remove obsolete SENSEDGE files if they exist to keep only the single output
$ObsoleteFile1 = Join-Path $OutputDir "APPLICATION_FOR_SENSEDGE.zip"
$ObsoleteFile2 = Join-Path $OutputDir "APPLICATION_FOR_SENSEDGE_Setup.exe"

if (Test-Path $ObsoleteFile1) {
    Remove-Item $ObsoleteFile1 -Force
    Write-Host "Cleaned up old file: APPLICATION_FOR_SENSEDGE.zip" -ForegroundColor Gray
}
if (Test-Path $ObsoleteFile2) {
    Remove-Item $ObsoleteFile2 -Force
    Write-Host "Cleaned up old file: APPLICATION_FOR_SENSEDGE_Setup.exe" -ForegroundColor Gray
}

# 1. Zip output file
$RdpmsZip = Join-Path $OutputDir "RDPMS_Serial_Monitor_v2.0.0.zip"

Write-Host "[1/2] Creating RDPMS_Serial_Monitor_v2.0.0.zip..." -ForegroundColor Yellow
if (Test-Path $RdpmsZip) { Remove-Item $RdpmsZip -Force }
Compress-Archive -Path "$ReleaseBuildDir\*" -DestinationPath $RdpmsZip -Force

# 2. Compile Inno Setup Installer
if (Test-Path $InnoCompiler) {
    Write-Host "[2/2] Compiling RDPMS_Serial_Monitor_v2.0.0_Setup.exe with Inno Setup..." -ForegroundColor Yellow
    $IssScript = Join-Path $WorkspaceRoot "serial_monitor\installer.iss"
    & $InnoCompiler $IssScript

    Write-Host "`nSuccessfully generated build zip & Inno setup installer in:" -ForegroundColor Green
    Write-Host "$OutputDir" -ForegroundColor Green
} else {
    Write-Warning "Inno Setup Compiler not found at $InnoCompiler. Zip created, but .exe installer was skipped."
}
