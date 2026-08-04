$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $workspace 'build\windows\x64\runner\Release'
$iss = Join-Path $workspace 'installer\forge-vpn.iss'
$pubspec = Join-Path $workspace 'pubspec.yaml'
$singBoxVersion = '1.13.16'
$singBoxCacheDir = Join-Path $workspace 'tools\sing-box'
$cachedSingBox = Join-Path $singBoxCacheDir "sing-box-$singBoxVersion-windows-amd64.exe"
$versionLine = Get-Content -LiteralPath $pubspec | Where-Object { $_ -match '^version:\s*([^+\s]+)' } | Select-Object -First 1
if (-not $versionLine -or $versionLine -notmatch '^version:\s*([^+\s]+)') {
  throw "Unable to read app version from $pubspec"
}
$appVersion = $Matches[1]
$iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
  $iscc = @(
    'E:\DevTools\Inno Setup 7\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $iscc) {
  throw 'Inno Setup compiler iscc.exe was not found.'
}

Push-Location $workspace
try {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows build failed with exit code $LASTEXITCODE"
  }
  $singBoxPath = Join-Path $releaseDir 'sing-box.exe'
  if (-not (Test-Path $singBoxPath)) {
    if (Test-Path $cachedSingBox) {
      Write-Host "Using cached sing-box v$singBoxVersion."
      Copy-Item $cachedSingBox $singBoxPath -Force
    } else {
      $archive = Join-Path $env:TEMP "sing-box-$singBoxVersion-windows-amd64.zip"
      $extractDir = Join-Path $env:TEMP "sing-box-$singBoxVersion-windows-amd64"
      $url = "https://github.com/SagerNet/sing-box/releases/download/v$singBoxVersion/sing-box-$singBoxVersion-windows-amd64.zip"
      Write-Host "Downloading sing-box v$singBoxVersion for Windows x64 (first build only)..."
      Invoke-WebRequest -Uri $url -OutFile $archive
      if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
      New-Item -ItemType Directory -Path $extractDir | Out-Null
      Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
      $downloadedCore = Get-ChildItem $extractDir -Filter 'sing-box.exe' -Recurse | Select-Object -First 1
      if (-not $downloadedCore) {
        throw "Downloaded sing-box archive does not contain sing-box.exe"
      }
      New-Item -ItemType Directory -Path $singBoxCacheDir -Force | Out-Null
      Copy-Item $downloadedCore.FullName $cachedSingBox -Force
      Copy-Item $cachedSingBox $singBoxPath -Force
      Remove-Item $archive -Force -ErrorAction SilentlyContinue
      Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  if (-not (Test-Path $singBoxPath)) {
    throw "Release directory is missing sing-box.exe: $releaseDir"
  }
  & $iscc "/DMyAppVersion=$appVersion" $iss
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
  }
  Write-Host "Installer generated in $workspace\dist"
}
finally {
  Pop-Location
}
