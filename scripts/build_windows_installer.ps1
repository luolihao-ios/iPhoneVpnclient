$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $workspace 'build\windows\x64\runner\Release'
$iss = Join-Path $workspace 'installer\forge-vpn.iss'
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
  if (-not (Test-Path (Join-Path $releaseDir 'sing-box.exe'))) {
    throw "Release directory is missing sing-box.exe: $releaseDir"
  }
  & $iscc $iss
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
  }
  Write-Host "Installer generated in $workspace\dist"
}
finally {
  Pop-Location
}
