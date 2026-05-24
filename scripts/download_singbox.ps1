# Download sing-box.exe for Windows and place it in assets/bin/
# Run from the vpn_client project root:
#   powershell -ExecutionPolicy Bypass -File scripts\download_singbox.ps1

param(
    [string]$Version = "1.11.0"
)

$ErrorActionPreference = "Stop"
$outDir  = "$PSScriptRoot\..\assets\bin"
$outFile = "$outDir\sing-box.exe"
$url     = "https://github.com/SagerNet/sing-box/releases/download/v$Version/sing-box-${Version}-windows-amd64.zip"

if (Test-Path $outFile) {
    Write-Host "sing-box.exe already exists at $outFile"
    exit 0
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$zip = "$env:TEMP\sing-box.zip"
Write-Host "Downloading sing-box v$Version from GitHub..."
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

Write-Host "Extracting..."
Expand-Archive -Path $zip -DestinationPath "$env:TEMP\sing-box-extract" -Force
$exe = Get-ChildItem "$env:TEMP\sing-box-extract" -Recurse -Filter "sing-box.exe" | Select-Object -First 1
Copy-Item $exe.FullName -Destination $outFile

Remove-Item $zip -Force
Remove-Item "$env:TEMP\sing-box-extract" -Recurse -Force

Write-Host "Done: $outFile"
