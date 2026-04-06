param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
  [string]$RemoteHost = '43.99.59.107',
  [string]$RemoteUser = 'ecs-user',
  [string]$KeyPath = 'C:\Users\kl\.ssh\id_rsa',
  [string]$RemotePublicDir = '/var/lib/family_teacher_remote/public',
  [string]$DownloadBaseUrl = 'https://api.tutor1on1.org/downloads',
  [switch]$SkipBuild,
  [switch]$SkipUpload,
  [switch]$SkipPromptAssetTests,
  [switch]$SkipZipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Action
  )
  Write-Host "==> $Label"
  Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
  & $Action
  if ((Test-Path -LiteralPath variable:global:LASTEXITCODE) -and $global:LASTEXITCODE -ne 0) {
    throw "$Label failed with exit code $LASTEXITCODE."
  }
}

function Get-FirstSha256FromOutput {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Lines,
    [Parameter(Mandatory = $true)]
    [string]$Context
  )
  $match = ($Lines | Select-String -Pattern '(?<hash>[0-9a-fA-F]{64})').Matches | Select-Object -First 1
  if ($null -eq $match) {
    throw "Could not parse SHA256 output for $Context."
  }
  return $match.Groups['hash'].Value.ToLowerInvariant()
}

function Assert-Http200 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [string]$Label,
    [int]$MaxAttempts = 5,
    [int]$RetryDelaySeconds = 5
  )
  $lastExitCode = 0
  $lastHeaders = @()
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "==> Verify URL ($Label) attempt $attempt/${MaxAttempts}: $Url"
    $headers = & curl.exe -k -I --max-time 20 $Url
    $lastExitCode = $LASTEXITCODE
    $lastHeaders = @($headers)
    $lastHeaders | ForEach-Object { Write-Host $_ }
    if ($lastExitCode -eq 0 -and ($lastHeaders -match 'HTTP/\d\.\d 200 OK')) {
      return
    }
    if ($attempt -lt $MaxAttempts) {
      Write-Host "URL check did not succeed for $Label. Retry in $RetryDelaySeconds second(s)."
      Start-Sleep -Seconds $RetryDelaySeconds
    }
  }
  if ($lastExitCode -ne 0) {
    throw "curl header check failed for $Label with exit code $lastExitCode after $MaxAttempts attempt(s)."
  }
  throw "URL check failed for $Label after $MaxAttempts attempt(s). Expected HTTP 200: $Url"
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
if (-not (Test-Path -LiteralPath $repoRoot)) {
  throw "Project root not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $KeyPath)) {
  throw "SSH key file not found: $KeyPath"
}

$versionUtilsScript = Join-Path $repoRoot 'scripts\public_release_version_utils.ps1'
if (-not (Test-Path -LiteralPath $versionUtilsScript)) {
  throw "Public release version utils not found: $versionUtilsScript"
}
. $versionUtilsScript
$assetNames = Get-PublicReleaseAssetNames -RepoRoot $repoRoot
$versionInfo = $assetNames.VersionInfo
$publishedZipName = $assetNames.WindowsFileName
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$zipPath = Join-Path $repoRoot ("build\" + $publishedZipName)
$downloadUrl = "$($DownloadBaseUrl.TrimEnd('/'))/$publishedZipName"
$tmpRemoteZip = "/tmp/$publishedZipName"
$zipBaseName = [System.IO.Path]::GetFileNameWithoutExtension($publishedZipName) -replace "-$([regex]::Escape($versionInfo.DisplayVersion))$", ''
$versionedCleanupPattern = "$zipBaseName-*.zip"
$candidateZipName = "${zipBaseName}_candidate.zip"
$candidateDownloadUrl = "$($DownloadBaseUrl.TrimEnd('/'))/$candidateZipName"
$legacyCleanupPattern = 'family_teacher*.zip'
$zipValidatorScript = Join-Path $repoRoot 'skills\windows_release_publish\scripts\validate_windows_release_zip.ps1'
$windowsBuildRoot = Join-Path $repoRoot 'build\windows'
$expectedExeName = 'tutor1on1.exe'
$legacyExeNames = @('family_teacher.exe', 'Tutor1on1.exe')

Push-Location $repoRoot
try {
  if (-not $SkipPromptAssetTests.IsPresent) {
    Invoke-Checked -Label 'flutter test test/prompt_assets_integrity_test.dart' -Action {
      flutter test test/prompt_assets_integrity_test.dart
    }
  } else {
    Write-Host '==> Skip prompt asset tests requested'
  }

  if (-not $SkipBuild.IsPresent) {
    if (Test-Path -LiteralPath $windowsBuildRoot) {
      Write-Host "==> Remove stale Windows build tree: $windowsBuildRoot"
      Remove-Item -LiteralPath $windowsBuildRoot -Recurse -Force
    }
    Invoke-Checked -Label 'flutter build windows --release' -Action {
      flutter build windows --release
    }
  } else {
    Write-Host '==> Skip build requested'
  }

  if (-not (Test-Path -LiteralPath $releaseDir)) {
    throw "Release directory not found: $releaseDir"
  }

  $expectedExePath = Join-Path $releaseDir $expectedExeName
  if (-not (Test-Path -LiteralPath $expectedExePath)) {
    throw "Expected Windows executable not found: $expectedExePath"
  }
  foreach ($legacyExeName in $legacyExeNames) {
    $legacyExePath = Join-Path $releaseDir $legacyExeName
    if ([string]::Equals($legacyExePath, $expectedExePath, [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    if (Test-Path -LiteralPath $legacyExePath) {
      Write-Host "==> Remove stale legacy executable: $legacyExePath"
      Remove-Item -LiteralPath $legacyExePath -Force
    }
  }

  if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
  }
  Invoke-Checked -Label "Create ZIP: $zipPath" -Action {
    New-ExplorerCompatibleZip -SourceDir $releaseDir -DestinationZip $zipPath
  }

  $zipItem = Get-Item -LiteralPath $zipPath
  if ($zipItem.Length -le 0) {
    throw "ZIP file is empty: $zipPath"
  }
  $localHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Host "Local ZIP size: $($zipItem.Length) bytes"
  Write-Host "Local SHA256: $localHash"

  if (-not $SkipZipValidation.IsPresent) {
    Invoke-Checked -Label 'Validate packaged ZIP artifact' -Action {
      powershell -ExecutionPolicy Bypass -File $zipValidatorScript -ZipPath $zipPath
    }
  } else {
    Write-Host '==> Skip ZIP artifact validation requested'
  }

  if ($SkipUpload.IsPresent) {
    Write-Host '==> Skip upload requested'
    Write-Host "ZIP ready: $zipPath"
    return
  }

  Invoke-Checked -Label 'Upload ZIP to remote /tmp' -Action {
    scp `
      -i $KeyPath `
      -o 'IdentitiesOnly=yes' `
      -o 'BatchMode=yes' `
      -o 'StrictHostKeyChecking=accept-new' `
      $zipPath `
      "${RemoteUser}@${RemoteHost}:$tmpRemoteZip"
  }

  $remoteCanaryCommand = @(
    "/usr/bin/ls -la '$tmpRemoteZip'",
    "/usr/bin/sudo /usr/bin/install -m 0644 -o root -g root '$tmpRemoteZip' '$RemotePublicDir/$candidateZipName'",
    "/usr/bin/sudo /usr/bin/sha256sum '$RemotePublicDir/$candidateZipName'",
    "/usr/bin/sudo /usr/bin/ls -la '$RemotePublicDir'",
    "/usr/bin/rm -f '$tmpRemoteZip'"
  ) -join '; '

  Write-Host '==> Install candidate ZIP on remote'
  $remoteCanaryOutput = & ssh `
    -i $KeyPath `
    -o 'IdentitiesOnly=yes' `
    -o 'BatchMode=yes' `
    -o 'StrictHostKeyChecking=accept-new' `
    "$RemoteUser@$RemoteHost" `
    $remoteCanaryCommand
  if ($LASTEXITCODE -ne 0) {
    throw "Remote candidate install command failed with exit code $LASTEXITCODE."
  }
  $remoteCanaryOutput | ForEach-Object { Write-Host $_ }

  $remoteCanaryHash = Get-FirstSha256FromOutput -Lines $remoteCanaryOutput -Context 'remote canary'
  if ($remoteCanaryHash -ne $localHash) {
    throw "Remote canary SHA256 mismatch. local=$localHash remote=$remoteCanaryHash"
  }
  Write-Host "Remote canary SHA256 matches local: $remoteCanaryHash"

  Assert-Http200 -Url $candidateDownloadUrl -Label 'candidate'

  $remotePromoteCommand = @(
    "/usr/bin/sudo /usr/bin/install -m 0644 -o root -g root '$RemotePublicDir/$candidateZipName' '$RemotePublicDir/$publishedZipName'",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$versionedCleanupPattern' ! -name '$publishedZipName' -print -delete",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$legacyCleanupPattern' -print -delete",
    "/usr/bin/sudo /usr/bin/rm -f '$RemotePublicDir/Tutor1on1.zip'",
    "/usr/bin/sudo /usr/bin/rm -f '$RemotePublicDir/$candidateZipName'",
    "/usr/bin/sudo /usr/bin/sha256sum '$RemotePublicDir/$publishedZipName'",
    "/usr/bin/sudo /usr/bin/ls -la '$RemotePublicDir'"
  ) -join '; '

  Write-Host '==> Promote candidate to canonical ZIP + cleanup old ZIPs'
  $remotePromoteOutput = & ssh `
    -i $KeyPath `
    -o 'IdentitiesOnly=yes' `
    -o 'BatchMode=yes' `
    -o 'StrictHostKeyChecking=accept-new' `
    "$RemoteUser@$RemoteHost" `
    $remotePromoteCommand
  if ($LASTEXITCODE -ne 0) {
    throw "Remote promote command failed with exit code $LASTEXITCODE."
  }
  $remotePromoteOutput | ForEach-Object { Write-Host $_ }

  $remoteHash = Get-FirstSha256FromOutput -Lines $remotePromoteOutput -Context 'remote published'
  if ($remoteHash -ne $localHash) {
    throw "Remote published SHA256 mismatch. local=$localHash remote=$remoteHash"
  }
  Write-Host "Remote published SHA256 matches local: $remoteHash"

  Assert-Http200 -Url $downloadUrl -Label 'versioned'

  Write-Host '==> Publish completed'
  Write-Host "Download URL: $downloadUrl"
  Write-Host "SHA256: $localHash"
} finally {
  Pop-Location
}
