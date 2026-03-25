param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$ReleaseTag = 'v1.0',
  [switch]$SkipPubGet,
  [switch]$SkipAnalyze,
  [switch]$SkipTest,
  [switch]$SkipAndroidBuild,
  [switch]$SkipWindowsBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Action
  )

  Write-Host "==> $Label"
  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed with exit code $LASTEXITCODE."
  }
}

$repoRoot = (Resolve-Path $ProjectRoot).Path
$distRoot = Join-Path $repoRoot "public_release\dist\$ReleaseTag"
$apkSource = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
$windowsReleaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$apkTarget = Join-Path $distRoot 'Tutor1on1.apk'
$zipTarget = Join-Path $distRoot 'Tutor1on1.zip'
$checksumsPath = Join-Path $distRoot 'SHA256SUMS.txt'

Push-Location $repoRoot
try {
  if (-not $SkipPubGet.IsPresent) {
    Invoke-Checked -Label 'flutter pub get' -Action {
      flutter pub get
    }
  }

  if (-not $SkipAnalyze.IsPresent) {
    Invoke-Checked -Label 'flutter analyze' -Action {
      flutter analyze
    }
  }

  if (-not $SkipTest.IsPresent) {
    Invoke-Checked -Label 'flutter test' -Action {
      flutter test
    }
  }

  if (-not $SkipAndroidBuild.IsPresent) {
    Invoke-Checked -Label 'flutter build apk --release' -Action {
      flutter build apk --release
    }
  }

  if (-not $SkipWindowsBuild.IsPresent) {
    Invoke-Checked -Label 'flutter build windows --release' -Action {
      flutter build windows --release
    }
  }

  if (-not (Test-Path $apkSource)) {
    throw "Missing Android artifact: $apkSource"
  }
  if (-not (Test-Path $windowsReleaseDir)) {
    throw "Missing Windows release directory: $windowsReleaseDir"
  }
  if (-not (Test-Path (Join-Path $windowsReleaseDir 'Tutor1on1.exe'))) {
    throw "Missing Windows executable under: $windowsReleaseDir"
  }

  if (Test-Path $distRoot) {
    Remove-Item -Recurse -Force $distRoot
  }
  New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

  Copy-Item -Path $apkSource -Destination $apkTarget -Force

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path $zipTarget) {
    Remove-Item -Force $zipTarget
  }
  [System.IO.Compression.ZipFile]::CreateFromDirectory(
    $windowsReleaseDir,
    $zipTarget,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
  )

  $hashLines = @(
    Get-FileHash -Algorithm SHA256 $apkTarget
    Get-FileHash -Algorithm SHA256 $zipTarget
  ) | ForEach-Object {
    "$($_.Hash.ToLowerInvariant())  $($_.Path | Split-Path -Leaf)"
  }
  Set-Content -Path $checksumsPath -Value $hashLines

  Write-Host "Created release artifacts in $distRoot"
  Write-Host 'Files: Tutor1on1.apk, Tutor1on1.zip, SHA256SUMS.txt'
} finally {
  Pop-Location
}
