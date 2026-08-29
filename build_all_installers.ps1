# PowerShell script to package build zips and generate Inno Setup installers for both applications
param (
    [string]$InnoCompiler = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Building Zips and Inno Setup Installers  " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

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

# 1. Zip output files
$RdpmsZip = Join-Path $OutputDir "RDPMS_Serial_Monitor_v2.0.0.zip"
$SensedgeZip = Join-Path $OutputDir "APPLICATION_FOR_SENSEDGE.zip"

Write-Host "[1/4] Creating RDPMS_Serial_Monitor_v2.0.0.zip..." -ForegroundColor Yellow
if (Test-Path $RdpmsZip) { Remove-Item $RdpmsZip -Force }
Compress-Archive -Path "$ReleaseBuildDir\*" -DestinationPath $RdpmsZip -Force

Write-Host "[2/4] Creating APPLICATION_FOR_SENSEDGE.zip..." -ForegroundColor Yellow
if (Test-Path $SensedgeZip) { Remove-Item $SensedgeZip -Force }
Compress-Archive -Path "$ReleaseBuildDir\*" -DestinationPath $SensedgeZip -Force

# 2. Compile Inno Setup Installers
if (Test-Path $InnoCompiler) {
    Write-Host "[3/4] Compiling RDPMS_Serial_Monitor_v2.0.0_Setup.exe with Inno Setup..." -ForegroundColor Yellow
    $IssScript1 = Join-Path $WorkspaceRoot "serial_monitor\installer.iss"
    & $InnoCompiler $IssScript1

    Write-Host "[4/4] Compiling APPLICATION_FOR_SENSEDGE_Setup.exe with Inno Setup..." -ForegroundColor Yellow
    $IssScript2 = Join-Path $WorkspaceRoot "serial_monitor\sensedge_installer.iss"
    & $InnoCompiler $IssScript2

    Write-Host "`nSuccessfully generated all build zips & Inno setup installers in:" -ForegroundColor Green
    Write-Host "$OutputDir" -ForegroundColor Green
} else {
    Write-Warning "Inno Setup Compiler not found at $InnoCompiler. Zips created, but .exe installers were skipped."
}

