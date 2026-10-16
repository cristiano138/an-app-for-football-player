# ============================================================
# Publish new version: copy apk to site folder + write update.json
# (ASCII only on purpose: PowerShell 5.1 misreads BOM-less UTF-8)
#
# Usage (run in any terminal):
#   powershell -ExecutionPolicy Bypass -File publish_new_version.ps1 `
#     -Version 1.0.3 -Code 4 -Notes "fix bugs" `
#     -Apk "E:\...\app-release.apk" [-Arm64Apk "E:\...\app-arm64-v8a-release.apk"]
#
# IMPORTANT: pubspec.yaml version must match: version: <Version>+<Code>
# ============================================================
param(
  [Parameter(Mandatory=$true)][string]$Version,
  [Parameter(Mandatory=$true)][int]$Code,
  [Parameter(Mandatory=$true)][string]$Apk,
  [string]$Arm64Apk = "",
  [string]$Notes = ""
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

if (-not (Test-Path $Apk)) { Write-Host "ERROR: apk not found: $Apk"; exit 1 }

# Find the site folder = the sub folder that already contains update.json
$site = Get-ChildItem $root -Directory |
  Where-Object { Test-Path (Join-Path $_.FullName "update.json") } |
  Select-Object -First 1
if (-not $site) { Write-Host "ERROR: site folder (with update.json) not found under $root"; exit 1 }

# 1) Copy universal apk (old apks are kept as archive, never deleted)
$apkName = "football-v$Version.apk"
Copy-Item $Apk (Join-Path $site.FullName $apkName) -Force
Write-Host "COPIED: $apkName -> $($site.FullName)"

# 2) Optional arm64-only small apk (~20MB, for in-app update on arm64 phones)
$armUrl = ""
if ($Arm64Apk -ne "") {
  if (-not (Test-Path $Arm64Apk)) { Write-Host "ERROR: arm64 apk not found: $Arm64Apk"; exit 1 }
  $armName = "football-v$Version-arm64.apk"
  Copy-Item $Arm64Apk (Join-Path $site.FullName $armName) -Force
  $armUrl = "https://football-daily-brief-22553.app.workbuddy.host/$armName"
  Write-Host "COPIED: $armName -> $($site.FullName)"
}

# 3) Write update.json (UTF-8 with BOM so App reads Chinese notes correctly)
$update = [ordered]@{
  version = $Version
  versionCode = $Code
  minVersionCode = 0
  apkUrl = "https://football-daily-brief-22553.app.workbuddy.host/$apkName"
}
if ($armUrl -ne "") { $update["apkUrlArm64"] = $armUrl }
$update["notes"] = $Notes
$json = $update | ConvertTo-Json
$jsonPath = Join-Path $site.FullName "update.json"
[System.IO.File]::WriteAllText($jsonPath, $json, (New-Object System.Text.UTF8Encoding $true))
Write-Host "WROTE: update.json"
Get-Content $jsonPath

Write-Host ""
Write-Host "NEXT STEPS:"
Write-Host "  1. Publish the site in WorkBuddy (appId wbapp_4HJ7ox5K1W6x2osGRzJO1L)"
Write-Host "  2. Verify: open https://football-daily-brief-22553.app.workbuddy.host/update.json?t=123 in browser"
Write-Host "     (must show the NEW version; if old content shows, wait a few minutes for CDN)"
Write-Host "  3. On an old phone: App -> Settings -> About -> Check update"
