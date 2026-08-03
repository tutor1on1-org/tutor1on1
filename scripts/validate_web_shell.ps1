param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LockedPackageVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LockPath,
    [Parameter(Mandatory = $true)]
    [string]$PackageName
  )

  $inPackage = $false
  foreach ($line in Get-Content -LiteralPath $LockPath) {
    if ($line -match '^  ([a-zA-Z0-9_]+):\s*$') {
      $inPackage = $Matches[1] -ceq $PackageName
      continue
    }
    if ($inPackage -and $line -match '^    version: "([^"]+)"\s*$') {
      return $Matches[1]
    }
  }
  throw "Package '$PackageName' is missing from $LockPath"
}

function Assert-FileHash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedSha256
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required Flutter Web file is missing: $Path"
  }
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if ($actual -cne $ExpectedSha256) {
    throw "Unexpected SHA-256 for ${Path}: $actual"
  }
}

$repoRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$webRoot = Join-Path $repoRoot 'web'
$lockPath = Join-Path $repoRoot 'pubspec.lock'

if (-not (Test-Path -LiteralPath $webRoot -PathType Container)) {
  throw "Flutter Web shell is missing: $webRoot"
}
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
  throw "pubspec.lock is missing: $lockPath"
}

$expectedVersions = [ordered]@{
  drift = '2.31.0'
  sqlite3 = '2.9.4'
}
foreach ($entry in $expectedVersions.GetEnumerator()) {
  $actualVersion = Get-LockedPackageVersion `
    -LockPath $lockPath `
    -PackageName $entry.Key
  if ($actualVersion -cne $entry.Value) {
    throw (
      "Pinned web asset version mismatch for $($entry.Key): " +
      "pubspec.lock has $actualVersion, expected $($entry.Value)."
    )
  }
}

$indexPath = Join-Path $webRoot 'index.html'
$manifestPath = Join-Path $webRoot 'manifest.json'
$serviceWorkerCleanupPath = Join-Path $webRoot 'disable_flutter_service_worker.js'
foreach ($requiredPath in @(
    $indexPath,
    $manifestPath,
    $serviceWorkerCleanupPath
  )) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required Flutter Web file is missing: $requiredPath"
  }
}

$indexText = [System.IO.File]::ReadAllText($indexPath)
if (-not $indexText.Contains('<base href="$FLUTTER_BASE_HREF">')) {
  throw 'web/index.html must use the Flutter base-href placeholder.'
}
if (-not $indexText.Contains('src="disable_flutter_service_worker.js"')) {
  throw 'web/index.html must load the legacy Flutter service-worker cleanup.'
}
if ($indexText.Contains('src="flutter_bootstrap.js"')) {
  throw 'web/index.html must not bypass service-worker cleanup when loading Flutter.'
}

$serviceWorkerCleanupText = [System.IO.File]::ReadAllText(
  $serviceWorkerCleanupPath
)
foreach ($requiredToken in @(
    'navigator.serviceWorker.getRegistrations()',
    'registration.unregister()',
    "'flutter-app-manifest'",
    "'flutter-temp-cache'",
    "'flutter-app-cache'",
    "new URL('/app/', window.location.origin)",
    'registration.scope.startsWith(appScope)',
    "script.src = 'flutter_bootstrap.js'"
  )) {
  if (-not $serviceWorkerCleanupText.Contains($requiredToken)) {
    throw "Service-worker cleanup is missing required token: $requiredToken"
  }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (
  $manifest.name -cne 'Tutor1on1' -or
  $manifest.id -cne '/app/' -or
  $manifest.start_url -cne '/app/' -or
  $manifest.scope -cne '/app/'
) {
  throw 'web/manifest.json has invalid Tutor1on1 PWA metadata.'
}

$workerPath = Join-Path $webRoot 'drift_worker.js'
$wasmPath = Join-Path $webRoot 'sqlite3.wasm'
Assert-FileHash `
  -Path $workerPath `
  -ExpectedSha256 'F0A9B87085F732FD7B6EE7EB34D3858C556F05D221EB1FEBFC443649CD365752'
Assert-FileHash `
  -Path $wasmPath `
  -ExpectedSha256 '922A76B182B6AF69B030C8E2FDD3283ECC8E827248B20E4B1F3F3DB170B52117'

$wasmBytes = [System.IO.File]::ReadAllBytes($wasmPath)
if (
  $wasmBytes.Length -lt 4 -or
  $wasmBytes[0] -ne 0x00 -or
  $wasmBytes[1] -ne 0x61 -or
  $wasmBytes[2] -ne 0x73 -or
  $wasmBytes[3] -ne 0x6d
) {
  throw 'web/sqlite3.wasm does not have a valid WebAssembly header.'
}

& node --check $workerPath
if ($LASTEXITCODE -ne 0) {
  throw "Drift worker JavaScript validation failed with exit code $LASTEXITCODE."
}
& node --check $serviceWorkerCleanupPath
if ($LASTEXITCODE -ne 0) {
  throw "Service-worker cleanup validation failed with exit code $LASTEXITCODE."
}

Write-Host 'PASS Flutter Web shell and pinned Drift assets'
