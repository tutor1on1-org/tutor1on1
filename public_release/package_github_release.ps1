param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$ReleaseTag,
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

function New-ExplorerCompatibleZip {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$DestinationZip
  )

  if (-not (Test-Path -LiteralPath $SourceDir)) {
    throw "ZIP source directory not found: $SourceDir"
  }
  if (Test-Path -LiteralPath $DestinationZip) {
    Remove-Item -LiteralPath $DestinationZip -Force
  }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $sourceRoot = (Resolve-Path -LiteralPath $SourceDir).Path.TrimEnd('\', '/')
  $files = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File
  $zipStream = [System.IO.File]::Open(
    $DestinationZip,
    [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
  )
  $archive = [System.IO.Compression.ZipArchive]::new(
    $zipStream,
    [System.IO.Compression.ZipArchiveMode]::Create,
    $false
  )
  try {
    foreach ($file in $files) {
      $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
      $entryName = $relativePath.Replace('\', '/')
      if ([string]::IsNullOrWhiteSpace($entryName)) {
        throw "Computed empty ZIP entry name for $($file.FullName)"
      }
      $entry = $archive.CreateEntry(
        $entryName,
        [System.IO.Compression.CompressionLevel]::Optimal
      )
      $entry.LastWriteTime = [DateTimeOffset]::new($file.LastWriteTimeUtc)
      $entryStream = $null
      $inputStream = $null
      try {
        $entryStream = $entry.Open()
        $inputStream = [System.IO.File]::OpenRead($file.FullName)
        $inputStream.CopyTo($entryStream)
      } finally {
        if ($inputStream -ne $null) {
          $inputStream.Dispose()
        }
        if ($entryStream -ne $null) {
          $entryStream.Dispose()
        }
      }
    }
  } finally {
    $archive.Dispose()
    $zipStream.Dispose()
  }
}

$repoRoot = (Resolve-Path $ProjectRoot).Path
$versionUtilsScript = Join-Path $repoRoot 'scripts\public_release_version_utils.ps1'
if (-not (Test-Path -LiteralPath $versionUtilsScript)) {
  throw "Public release version utils not found: $versionUtilsScript"
}
. $versionUtilsScript
if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
  $ReleaseTag = (Get-PublicReleaseVersionInfo -RepoRoot $repoRoot).ReleaseTag
}
$assetNames = Get-PublicReleaseAssetNames -RepoRoot $repoRoot
$distRoot = Join-Path $repoRoot "public_release\dist\$ReleaseTag"
$apkSource = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
$windowsReleaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$windowsBuildRoot = Join-Path $repoRoot 'build\windows'
$apkTarget = Join-Path $distRoot $assetNames.AndroidFileName
$zipTarget = Join-Path $distRoot $assetNames.WindowsFileName
$checksumsPath = Join-Path $distRoot $assetNames.ChecksumsFileName
$expectedExePath = Join-Path $windowsReleaseDir 'tutor1on1.exe'
$legacyExePaths = @(
  (Join-Path $windowsReleaseDir 'family_teacher.exe'),
  (Join-Path $windowsReleaseDir 'Tutor1on1.exe')
)
$zipValidatorScript = Join-Path $repoRoot 'skills\windows_release_publish\scripts\validate_windows_release_zip.ps1'

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
    if (Test-Path -LiteralPath $windowsBuildRoot) {
      Write-Host "==> Remove stale Windows build tree: $windowsBuildRoot"
      Remove-Item -LiteralPath $windowsBuildRoot -Recurse -Force
    }
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
  if (-not (Test-Path $expectedExePath)) {
    throw "Missing Windows executable under: $expectedExePath"
  }
  foreach ($legacyExePath in $legacyExePaths) {
    if ([string]::Equals($legacyExePath, $expectedExePath, [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    if (Test-Path $legacyExePath) {
      Write-Host "==> Remove stale legacy executable: $legacyExePath"
      Remove-Item -LiteralPath $legacyExePath -Force
    }
  }

  if (Test-Path $distRoot) {
    Remove-Item -Recurse -Force $distRoot
  }
  New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

  Copy-Item -Path $apkSource -Destination $apkTarget -Force

  New-ExplorerCompatibleZip -SourceDir $windowsReleaseDir -DestinationZip $zipTarget
  Invoke-Checked -Label 'Validate packaged Windows ZIP for GitHub release' -Action {
    powershell -ExecutionPolicy Bypass -File $zipValidatorScript -ZipPath $zipTarget
  }

  $hashLines = @(
    Get-FileHash -Algorithm SHA256 $apkTarget
    Get-FileHash -Algorithm SHA256 $zipTarget
  ) | ForEach-Object {
    "$($_.Hash.ToLowerInvariant())  $($_.Path | Split-Path -Leaf)"
  }
  Set-Content -Path $checksumsPath -Value $hashLines

  Write-Host "Created release artifacts in $distRoot"
  Write-Host "Files: $($assetNames.AndroidFileName), $($assetNames.WindowsFileName), $($assetNames.ChecksumsFileName)"
} finally {
  Pop-Location
}
