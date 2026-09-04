#!/usr/bin/env pwsh
<#
.SYNOPSIS
  The one entry point for this repository's checks. Bash twin: scripts/check.sh beside this file.
  The two are held to answering identically.

.DESCRIPTION
  One step, and a red one stops the run: build.ps1 in the root analyses, formats and tests every
  package of this tree, which is what .github/workflows/checks.yml runs on a push and what the
  release of ansiwise-cli runs once more before it builds a binary.
#>
$ErrorActionPreference = "Continue"

# The two verdict lines carry an em dash, and a console left on the machine's code page writes it
# out as a hyphen. Whoever greps for the line the bash twin prints would then not find it.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$Root = (git rev-parse --show-toplevel)
if (-not $Root) { exit 1 }
Set-Location $Root

function Fail($message) { Write-Host "check: FAIL — $message"; exit 1 }

Write-Host "check: every package analysed, formatted and tested."

# dart is named here rather than left to build.ps1. build.ps1 reads the exit code of each dart
# call, so a missing one leaves eleven packages reported as red and the reason on a line above
# each of them. A skipped check must never read like a check that ran.
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
  Fail "./build.ps1 — dart is not on this machine, so no package was analysed, formatted or tested. The version this organisation pins stands in ../ansiwise-core/tool/gate/pins.dart."
}

& (Join-Path $Root "build.ps1")
if ($LASTEXITCODE -ne 0) { Fail "./build.ps1 — a package above is red." }

Write-Host "check: OK — every check green"
