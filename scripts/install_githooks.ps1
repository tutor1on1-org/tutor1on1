param(
  [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$hooksPath = ".githooks"

Push-Location $repoRoot
try {
  if (-not $VerifyOnly) {
    & git config core.hooksPath $hooksPath
  }

  $configuredPath = (& git config --get core.hooksPath).Trim()
  if ($configuredPath -ne $hooksPath) {
    throw "core.hooksPath is '$configuredPath', expected '$hooksPath'"
  }

  Write-Output "Configured git hooks path: $configuredPath"
} finally {
  Pop-Location
}
