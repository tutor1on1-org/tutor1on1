param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$RemoteHost = '43.99.59.107',
  [string]$RemoteUser = 'ecs-user',
  [string]$KeyPath = 'C:\Users\kl\.ssh\id_rsa',
  [string]$RemotePublicDir = '/var/lib/family_teacher_remote/public',
  [string]$DownloadBaseUrl = 'https://api.tutor1on1.org/downloads',
  [string]$ApkName = 'Tutor1on1.apk',
  [switch]$SkipBuild
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

$versionInfo = Get-PublicReleaseVersionInfo -RepoRoot $repoRoot
$releaseApkPath = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
$canonicalLocalApkPath = Join-Path $repoRoot ("build\" + $ApkName)
$downloadUrl = "$($DownloadBaseUrl.TrimEnd('/'))/$ApkName"
$tmpRemoteApk = "/tmp/$ApkName"
$apkBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ApkName)
$versionedApkName = "${apkBaseName}-$($versionInfo.DisplayVersion).apk"
$versionedDownloadUrl = "$($DownloadBaseUrl.TrimEnd('/'))/$versionedApkName"
$candidateApkName = "${apkBaseName}_candidate.apk"
$candidateDownloadUrl = "$($DownloadBaseUrl.TrimEnd('/'))/$candidateApkName"
$versionedCleanupPattern = "$apkBaseName-*.apk"
$legacyCleanupPattern = 'family_teacher*.apk'

Push-Location $repoRoot
try {
  if (-not $SkipBuild.IsPresent) {
    Invoke-Checked -Label 'flutter build apk --config-only' -Action {
      flutter build apk --config-only
    }
    Invoke-Checked -Label 'flutter build apk --release' -Action {
      flutter build apk --release
    }
  } else {
    Write-Host '==> Skip build requested'
  }

  if (-not (Test-Path -LiteralPath $releaseApkPath)) {
    throw "Release APK not found: $releaseApkPath"
  }

  Copy-Item -LiteralPath $releaseApkPath -Destination $canonicalLocalApkPath -Force
  $apkItem = Get-Item -LiteralPath $canonicalLocalApkPath
  if ($apkItem.Length -le 0) {
    throw "APK file is empty: $canonicalLocalApkPath"
  }
  $localHash = (Get-FileHash -LiteralPath $canonicalLocalApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Host "Local APK size: $($apkItem.Length) bytes"
  Write-Host "Local SHA256: $localHash"

  Invoke-Checked -Label 'Upload APK to remote /tmp' -Action {
    scp `
      -i $KeyPath `
      -o 'IdentitiesOnly=yes' `
      -o 'BatchMode=yes' `
      -o 'StrictHostKeyChecking=accept-new' `
      $canonicalLocalApkPath `
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
    "/usr/bin/sudo /usr/bin/install -m 0644 -o root -g root '$RemotePublicDir/$candidateApkName' '$RemotePublicDir/$ApkName'",
    "/usr/bin/sudo /usr/bin/install -m 0644 -o root -g root '$RemotePublicDir/$candidateApkName' '$RemotePublicDir/$versionedApkName'",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$versionedCleanupPattern' ! -name '$versionedApkName' -print -delete",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$legacyCleanupPattern' -print -delete",
    "/usr/bin/sudo /usr/bin/rm -f '$RemotePublicDir/$candidateApkName'",
    "/usr/bin/sudo /usr/bin/sha256sum '$RemotePublicDir/$ApkName'",
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

  $remoteHash = Get-FirstSha256FromOutput -Lines $remotePromoteOutput -Context 'remote canonical'
  if ($remoteHash -ne $localHash) {
    throw "Remote canonical SHA256 mismatch. local=$localHash remote=$remoteHash"
  }
  Write-Host "Remote canonical SHA256 matches local: $remoteHash"

  Assert-Http200 -Url $downloadUrl -Label 'canonical'
  Assert-Http200 -Url $versionedDownloadUrl -Label 'versioned'

  Write-Host '==> Publish completed'
  Write-Host "Download URL: $downloadUrl"
  Write-Host "Versioned download URL: $versionedDownloadUrl"
  Write-Host "SHA256: $localHash"
} finally {
  Pop-Location
}
