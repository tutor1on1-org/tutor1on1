param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$ReleaseTag,
  [switch]$SkipPubGet,
  [switch]$SkipAnalyze,
  [switch]$SkipTest,
  [switch]$CleanWindowsBuild,
  [switch]$SkipAndroidBuild,
  [switch]$SkipWindowsBuild,
  [switch]$UseExistingPublishedArtifacts
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
if ($ReleaseTag -cnotmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') {
  throw "Invalid release tag: $ReleaseTag"
}
$assetNames = Get-PublicReleaseAssetNames -RepoRoot $repoRoot
$distBase = [System.IO.Path]::GetFullPath(
  (Join-Path $repoRoot 'public_release\dist')
).TrimEnd('\', '/')
$distRoot = [System.IO.Path]::GetFullPath((Join-Path $distBase $ReleaseTag))
$distPrefix = $distBase + [System.IO.Path]::DirectorySeparatorChar
if (-not $distRoot.StartsWith(
    $distPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw "Release dist path escaped its root: $distRoot"
}
$apkSource = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
$publishedApkSource = Join-Path $repoRoot ("build\" + $assetNames.AndroidFileName)
$windowsReleaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$windowsBuildRoot = Join-Path $repoRoot 'build\windows'
$publishedZipSource = Join-Path $repoRoot ("build\" + $assetNames.WindowsFileName)
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
  if ($UseExistingPublishedArtifacts.IsPresent) {
    Write-Host '==> Reuse the exact APK and ZIP bytes already published by the platform steps'
    foreach ($artifactPath in @($publishedApkSource, $publishedZipSource)) {
      if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "Published artifact not found: $artifactPath"
      }
      if ((Get-Item -LiteralPath $artifactPath).Length -le 0) {
        throw "Published artifact is empty: $artifactPath"
      }
    }
  } elseif (-not $SkipPubGet.IsPresent) {
    Invoke-Checked -Label 'flutter pub get' -Action {
      flutter pub get
    }
  }

  if (-not $UseExistingPublishedArtifacts.IsPresent -and -not $SkipAnalyze.IsPresent) {
    Invoke-Checked -Label 'flutter analyze --no-pub' -Action {
      flutter analyze --no-pub
    }
  }

  if (-not $UseExistingPublishedArtifacts.IsPresent -and -not $SkipTest.IsPresent) {
    Invoke-Checked -Label 'flutter test --no-pub' -Action {
      flutter test --no-pub
    }
  }

  if (-not $UseExistingPublishedArtifacts.IsPresent -and -not $SkipAndroidBuild.IsPresent) {
    Invoke-Checked -Label 'flutter build apk --release --no-pub' -Action {
      flutter build apk --release --no-pub
    }
  }

  if (-not $UseExistingPublishedArtifacts.IsPresent -and -not $SkipWindowsBuild.IsPresent) {
    if ($CleanWindowsBuild.IsPresent -and (Test-Path -LiteralPath $windowsBuildRoot)) {
      Write-Host "==> Remove stale Windows build tree: $windowsBuildRoot"
      Remove-Item -LiteralPath $windowsBuildRoot -Recurse -Force
    } elseif ($CleanWindowsBuild.IsPresent) {
      Write-Host "==> Clean Windows build requested, but build tree is already absent: $windowsBuildRoot"
    } else {
      Write-Host "==> Reuse existing Windows build tree when possible: $windowsBuildRoot"
    }
    Invoke-Checked -Label 'flutter build windows --release --no-pub' -Action {
      flutter build windows --release --no-pub
    }
  }

  if (-not $UseExistingPublishedArtifacts.IsPresent -and -not (Test-Path $apkSource)) {
    throw "Missing Android artifact: $apkSource"
  }
  if (-not $UseExistingPublishedArtifacts.IsPresent -and -not (Test-Path $windowsReleaseDir)) {
    throw "Missing Windows release directory: $windowsReleaseDir"
  }
  if (-not $UseExistingPublishedArtifacts.IsPresent -and -not (Test-Path $expectedExePath)) {
    throw "Missing Windows executable under: $expectedExePath"
  }
  if (-not $UseExistingPublishedArtifacts.IsPresent) {
    foreach ($legacyExePath in $legacyExePaths) {
      if ([string]::Equals($legacyExePath, $expectedExePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
      }
      if (Test-Path $legacyExePath) {
        Write-Host "==> Remove stale legacy executable: $legacyExePath"
        Remove-Item -LiteralPath $legacyExePath -Force
      }
    }
  }

  if (Test-Path $distRoot) {
    Remove-Item -Recurse -Force $distRoot
  }
  New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

  if ($UseExistingPublishedArtifacts.IsPresent) {
    Copy-Item -LiteralPath $publishedApkSource -Destination $apkTarget -Force
    Copy-Item -LiteralPath $publishedZipSource -Destination $zipTarget -Force
  } else {
    Copy-Item -LiteralPath $apkSource -Destination $apkTarget -Force
    New-ExplorerCompatibleZip -SourceDir $windowsReleaseDir -DestinationZip $zipTarget
    Invoke-Checked -Label 'Validate packaged Windows ZIP for GitHub release' -Action {
      powershell -ExecutionPolicy Bypass -File $zipValidatorScript -ZipPath $zipTarget
    }
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
