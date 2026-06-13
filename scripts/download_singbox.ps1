# ВНИМАНИЕ: качает MAINLINE sing-box.exe от SagerNet (БЕЗ AmneziaWG/xhttp).
# Наш рабочий движок - ФОРК amnezia-box -> assets/bin/singbox-uni.exe, уже закоммичен.
# Здесь полезна только часть с wintun.dll (она тоже закоммичена в репо).
# Скрипт оставлен как reference; для рабочего клиента используйте singbox-uni.exe.
#
# Download sing-box.exe + wintun.dll for Windows and place them in assets/bin/ (reference).
# Run from the vpn_client project root:
#   powershell -ExecutionPolicy Bypass -File scripts\download_singbox.ps1

param(
    [string]$SingBoxVersion = "1.11.0",
    [string]$WinTunVersion  = "0.14.1"
)

$ErrorActionPreference = "Stop"
$outDir = "$PSScriptRoot\..\assets\bin"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# ── sing-box.exe ──────────────────────────────────────────────────────────────
$sbFile = "$outDir\sing-box.exe"
if (-not (Test-Path $sbFile)) {
    $sbUrl = "https://github.com/SagerNet/sing-box/releases/download/v$SingBoxVersion/sing-box-${SingBoxVersion}-windows-amd64.zip"
    $zip = "$env:TEMP\sing-box.zip"
    Write-Host "Downloading sing-box v$SingBoxVersion..."
    Invoke-WebRequest -Uri $sbUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath "$env:TEMP\sb-extract" -Force
    $exe = Get-ChildItem "$env:TEMP\sb-extract" -Recurse -Filter "sing-box.exe" | Select-Object -First 1
    Copy-Item $exe.FullName -Destination $sbFile
    Remove-Item $zip, "$env:TEMP\sb-extract" -Recurse -Force
    Write-Host "  -> $sbFile"
} else {
    Write-Host "sing-box.exe already present"
}

# ── wintun.dll ────────────────────────────────────────────────────────────────
$wtFile = "$outDir\wintun.dll"
if (-not (Test-Path $wtFile)) {
    $wtUrl = "https://www.wintun.net/builds/wintun-${WinTunVersion}.zip"
    $zip = "$env:TEMP\wintun.zip"
    Write-Host "Downloading WinTun v$WinTunVersion..."
    Invoke-WebRequest -Uri $wtUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath "$env:TEMP\wt-extract" -Force
    $dll = Get-ChildItem "$env:TEMP\wt-extract" -Recurse -Filter "wintun.dll" |
           Where-Object { $_.FullName -like "*amd64*" } | Select-Object -First 1
    Copy-Item $dll.FullName -Destination $wtFile
    Remove-Item $zip, "$env:TEMP\wt-extract" -Recurse -Force
    Write-Host "  -> $wtFile"
} else {
    Write-Host "wintun.dll already present"
}

Write-Host ""
Write-Host "Done. Run 'flutter build windows --release' to include these in the app."
