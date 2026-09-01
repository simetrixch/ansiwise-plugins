<#
.SYNOPSIS
  build.ps1 — prove every package of this repository locally, the way
  .github/workflows/checks.yml does. Bash twin: build.sh in this folder. The two are held to
  answering identically.

.DESCRIPTION
  THIS REPOSITORY BUILDS NOTHING. It holds the steps that touch a real machine, as passive parts of
  ansiwise-cli: no binary, no release, no tag of its own. "Building" it means proving it.

  ONE PACKAGE AT A TIME, BECAUSE THAT IS HOW THEY STAND. A dozen packages share this tree and each
  carries its own manifest. EVERY PACKAGE RUNS BEFORE ANYTHING IS REPORTED, so one red package does
  not hide the state of the eleven behind it.
#>
$ErrorActionPreference = 'Continue'
Set-Location (git rev-parse --show-toplevel)

$failed = $false
foreach ($manifest in Get-ChildItem -Path . -Depth 1 -Filter pubspec.yaml) {
  $package = $manifest.Directory
  if ($package.FullName -eq (Get-Location).Path) { continue }
  if (-not (Test-Path (Join-Path $package.FullName 'test'))) { continue }
  Write-Host "build: $($package.Name)"
  Push-Location $package.FullName
  dart pub get | Out-Null
  dart analyze --fatal-infos; if ($LASTEXITCODE -ne 0) { $failed = $true }
  dart format --output=none --set-exit-if-changed .; if ($LASTEXITCODE -ne 0) { $failed = $true }
  dart test; if ($LASTEXITCODE -ne 0) { $failed = $true }
  Pop-Location
}
if ($failed) { Write-Error 'build: FAIL — a package above is red'; exit 1 }
Write-Host 'build: OK — every package of this repository is green'
