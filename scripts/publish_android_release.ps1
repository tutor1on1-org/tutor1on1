param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$RemoteHost = '43.99.59.107',
  [string]$RemoteUser = 'ecs-user',
  [string]$KeyPath = 'C:\Users\kl\.ssh\id_rsa',
  [string]$RemotePublicDir = '/var/lib/family_teacher_remote/public',
  [string]$DownloadBaseUrl = 'https://api.tutor1on1.org/downloads',
  [switch]$SkipPubGet,
  [switch]$SkipBuild,
  [switch]$SkipUpload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$versionUtilsScript = Join-Path $PSScriptRoot 'public_release_version_utils.ps1'
if (-not (Test-Path -LiteralPath $versionUtilsScript)) {
  throw "Public release version utils not found: $versionUtilsScript"
}
. $versionUtilsScript

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
    [string]$Label
  )
  Write-Host "==> Verify URL ($Label): $Url"
  $headers = & curl.exe -k -I --max-time 20 $Url
  if ($LASTEXITCODE -ne 0) {
    throw "curl header check failed for $Label with exit code $LASTEXITCODE."
  }
  $headers | ForEach-Object { Write-Host $_ }
  if (-not ($headers -match 'HTTP/\d\.\d 200 OK')) {
    throw "URL check failed for $Label. Expected HTTP 200: $Url"
  }
}

$repoRoot = (Resolve-Path $ProjectRoot).Path
if (-not (Test-Path -LiteralPath $repoRoot)) {
  throw "Project root not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $KeyPath)) {
  throw "SSH key file not found: $KeyPath"
}

$assetNames = Get-PublicReleaseAssetNames -RepoRoot $repoRoot
$versionInfo = $assetNames.VersionInfo
$releaseApkPath = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
$publishedApkName = $assetNames.AndroidFileName
$localPublishedApkPath = Join-Path $repoRoot ("build\" + $publishedApkName)
$downloadUrl = "$($DownloadBaseUrl.TrimEnd('/'))/$publishedApkName"
$tmpRemoteApk = "/tmp/$publishedApkName"
$apkBaseName = [System.IO.Path]::GetFileNameWithoutExtension($publishedApkName) -replace "-$([regex]::Escape($versionInfo.DisplayVersion))$", ''
$candidateApkName = "${apkBaseName}_candidate.apk"
$candidateDownloadUrl = "$($DownloadBaseUrl.TrimEnd('/'))/$candidateApkName"
$versionedCleanupPattern = "$apkBaseName-*.apk"
$legacyCleanupPattern = 'family_teacher*.apk'

Push-Location $repoRoot
try {
  if (-not $SkipBuild.IsPresent) {
    if (-not $SkipPubGet.IsPresent) {
      Invoke-Checked -Label 'flutter pub get' -Action {
        flutter pub get
      }
    } else {
      Write-Host '==> Skip flutter pub get requested'
    }

    Invoke-Checked -Label 'flutter build apk --config-only' -Action {
      flutter build apk --config-only --no-pub
    }
    Invoke-Checked -Label 'flutter build apk --release' -Action {
      flutter build apk --release --no-pub
    }
  } else {
    Write-Host '==> Skip build requested'
  }

  if (-not (Test-Path -LiteralPath $releaseApkPath)) {
    throw "Release APK not found: $releaseApkPath"
  }

  Copy-Item -LiteralPath $releaseApkPath -Destination $localPublishedApkPath -Force
  $apkItem = Get-Item -LiteralPath $localPublishedApkPath
  if ($apkItem.Length -le 0) {
    throw "APK file is empty: $localPublishedApkPath"
  }
  $localHash = (Get-FileHash -LiteralPath $localPublishedApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Host "Local APK size: $($apkItem.Length) bytes"
  Write-Host "Local SHA256: $localHash"

  if ($SkipUpload.IsPresent) {
    Write-Host '==> Skip upload requested'
    Write-Host "APK ready: $localPublishedApkPath"
    Write-Host "Download URL: $downloadUrl"
    return
  }

  Invoke-Checked -Label 'Upload APK to remote /tmp' -Action {
    scp `
      -i $KeyPath `
      -o 'IdentitiesOnly=yes' `
      -o 'BatchMode=yes' `
      -o 'StrictHostKeyChecking=accept-new' `
      $localPublishedApkPath `
      "${RemoteUser}@${RemoteHost}:$tmpRemoteApk"
  }

  $remoteCandidateCommand = @(
    "/usr/bin/ls -la '$tmpRemoteApk'",
    "/usr/bin/sudo /usr/bin/install -m 0644 -o root -g root '$tmpRemoteApk' '$RemotePublicDir/$candidateApkName'",
    "/usr/bin/sudo /usr/bin/sha256sum '$RemotePublicDir/$candidateApkName'",
    "/usr/bin/rm -f '$tmpRemoteApk'",
    "/usr/bin/sudo /usr/bin/ls -la '$RemotePublicDir'"
  ) -join '; '

  Write-Host '==> Install candidate APK on remote'
  $remoteCandidateOutput = & ssh `
    -i $KeyPath `
    -o 'IdentitiesOnly=yes' `
    -o 'BatchMode=yes' `
    -o 'StrictHostKeyChecking=accept-new' `
    "$RemoteUser@$RemoteHost" `
    $remoteCandidateCommand
  if ($LASTEXITCODE -ne 0) {
    throw "Remote candidate install command failed with exit code $LASTEXITCODE."
  }
  $remoteCandidateOutput | ForEach-Object { Write-Host $_ }

  $remoteCandidateHash = Get-FirstSha256FromOutput -Lines $remoteCandidateOutput -Context 'remote candidate'
  if ($remoteCandidateHash -ne $localHash) {
    throw "Remote candidate SHA256 mismatch. local=$localHash remote=$remoteCandidateHash"
  }
  Write-Host "Remote candidate SHA256 matches local: $remoteCandidateHash"

  Assert-Http200 -Url $candidateDownloadUrl -Label 'candidate'

  $remotePromoteCommand = @(
    "/usr/bin/sudo /usr/bin/install -m 0644 -o root -g root '$RemotePublicDir/$candidateApkName' '$RemotePublicDir/$publishedApkName'",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$versionedCleanupPattern' ! -name '$publishedApkName' -print -delete",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$legacyCleanupPattern' -print -delete",
    "/usr/bin/sudo /usr/bin/rm -f '$RemotePublicDir/Tutor1on1.apk'",
    "/usr/bin/sudo /usr/bin/rm -f '$RemotePublicDir/$candidateApkName'",
    "/usr/bin/sudo /usr/bin/sha256sum '$RemotePublicDir/$publishedApkName'",
    "/usr/bin/sudo /usr/bin/ls -la '$RemotePublicDir'"
  ) -join '; '

  Write-Host '==> Promote candidate to canonical APK + cleanup old APKs'
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
