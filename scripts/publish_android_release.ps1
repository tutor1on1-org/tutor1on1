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

function Invoke-GradleAssembleRelease {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )
  Push-Location (Join-Path $RepoRoot 'android')
  try {
    .\gradlew.bat assembleRelease --no-daemon
    return $LASTEXITCODE
  } finally {
    Pop-Location
  }
}

function Invoke-GradleAssembleReleaseWithRetry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )
  Write-Host '==> gradlew assembleRelease'
  $exitCode = Invoke-GradleAssembleRelease -RepoRoot $RepoRoot
  if ($exitCode -ne 0) {
    Write-Host "==> gradlew assembleRelease failed with exit code $exitCode; retry once"
    $exitCode = Invoke-GradleAssembleRelease -RepoRoot $RepoRoot
  }
  if ($exitCode -ne 0) {
    throw "gradlew assembleRelease failed with exit code $exitCode."
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

function Repair-GeneratedPluginRegistrantForRelease {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $javaRegistrantPath = Join-Path $RepoRoot 'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'
  if (-not (Test-Path -LiteralPath $javaRegistrantPath)) {
    throw "GeneratedPluginRegistrant.java was not generated: $javaRegistrantPath"
  }

  $content = Get-Content -LiteralPath $javaRegistrantPath -Raw
  if ($content -match 'dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin') {
    $integrationTestBlockPattern = '(?ms)^\s*try\s*\{\s*\r?\n\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\r?\n\s*\}\s*catch \(Exception e\)\s*\{\s*\r?\n\s*Log\.e\(TAG, "Error registering plugin integration_test, dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin", e\);\s*\r?\n\s*\}\s*\r?\n'
    $updatedContent = [regex]::Replace($content, $integrationTestBlockPattern, '')
    if ($updatedContent -eq $content) {
      throw "Could not remove integration_test from GeneratedPluginRegistrant.java"
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($javaRegistrantPath, $updatedContent, $utf8NoBom)
    Write-Host "==> Remove release-only integration_test registrant block: $javaRegistrantPath"
    $content = $updatedContent
  }

  if ($content -match 'dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin') {
    throw "GeneratedPluginRegistrant.java still references integration_test after repair: $javaRegistrantPath"
  }
  if ($content -notmatch 'com\.it_nomads\.fluttersecurestorage\.FlutterSecureStoragePlugin') {
    throw "GeneratedPluginRegistrant.java is missing flutter_secure_storage registration: $javaRegistrantPath"
  }
}

function Assert-AndroidReleasePluginRegistration {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath
  )

  $resolvedApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
  $pythonScript = @'
import re
import struct
import sys
import zipfile

required_classes = {
    "Lio/flutter/plugins/GeneratedPluginRegistrant;",
    "Lcom/it_nomads/fluttersecurestorage/FlutterSecureStoragePlugin;",
}
required_strings = {
    "registerWith",
    "plugins.it_nomads.com/flutter_secure_storage",
}


def read_u4(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def read_dex_string(data, offset):
    pos = offset
    while data[pos] & 0x80:
        pos += 1
    pos += 1
    start = pos
    while data[pos] != 0:
        pos += 1
    return data[start:pos].decode("utf-8", errors="replace")


apk_path = sys.argv[1]
missing_classes = set(required_classes)
missing_strings = set(required_strings)
dex_entries = 0

with zipfile.ZipFile(apk_path) as archive:
    for name in archive.namelist():
        if not re.fullmatch(r"classes(\d*)\.dex", name.rsplit("/", 1)[-1]):
            continue
        dex_entries += 1
        dex = archive.read(name)

        for value in tuple(missing_strings):
            if value.encode("utf-8") in dex:
                missing_strings.discard(value)

        string_ids_off = read_u4(dex, 0x3C)
        type_ids_off = read_u4(dex, 0x44)
        class_defs_size = read_u4(dex, 0x60)
        class_defs_off = read_u4(dex, 0x64)

        for index in range(class_defs_size):
            if not missing_classes:
                break
            class_idx = read_u4(dex, class_defs_off + (32 * index))
            string_idx = read_u4(dex, type_ids_off + (4 * class_idx))
            string_data_off = read_u4(dex, string_ids_off + (4 * string_idx))
            missing_classes.discard(read_dex_string(dex, string_data_off))

if dex_entries <= 0:
    print(f"Release APK is missing classes*.dex entries: {apk_path}", file=sys.stderr)
    sys.exit(1)
if missing_classes or missing_strings:
    for value in sorted(missing_classes):
        print(f"Release APK dex is missing required class {value} in {apk_path}", file=sys.stderr)
    for value in sorted(missing_strings):
        print(f"Release APK dex is missing required string '{value}' in {apk_path}", file=sys.stderr)
    sys.exit(1)

print(f"==> APK plugin registration dex gate passed: {apk_path} ({dex_entries} dex file(s))")
'@
  $pythonOutput = $pythonScript | python - $resolvedApkPath 2>&1
  $pythonOutput | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) {
    throw "APK plugin registration dex gate failed with exit code $LASTEXITCODE."
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
$removeCanonicalApkCommand = if ([string]::Equals($publishedApkName, 'Tutor1on1.apk', [System.StringComparison]::OrdinalIgnoreCase)) {
  $null
} else {
  "/usr/bin/sudo /usr/bin/rm -f '$RemotePublicDir/Tutor1on1.apk'"
}

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

    Repair-GeneratedPluginRegistrantForRelease -RepoRoot $repoRoot

    Invoke-Checked -Label 'flutter build apk --config-only' -Action {
      flutter build apk --config-only --no-pub
    }
    Repair-GeneratedPluginRegistrantForRelease -RepoRoot $repoRoot
    Invoke-GradleAssembleReleaseWithRetry -RepoRoot $repoRoot
  } else {
    Write-Host '==> Skip build requested'
  }

  if (-not (Test-Path -LiteralPath $releaseApkPath)) {
    throw "Release APK not found: $releaseApkPath"
  }
  Assert-AndroidReleasePluginRegistration -ApkPath $releaseApkPath

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

  $remotePromoteCommands = @(
    "/usr/bin/sudo /usr/bin/install -m 0644 -o root -g root '$RemotePublicDir/$candidateApkName' '$RemotePublicDir/$publishedApkName'",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$versionedCleanupPattern' ! -name '$publishedApkName' -print -delete",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$legacyCleanupPattern' -print -delete",
    "/usr/bin/sudo /usr/bin/rm -f '$RemotePublicDir/$candidateApkName'",
    "/usr/bin/sudo /usr/bin/sha256sum '$RemotePublicDir/$publishedApkName'",
    "/usr/bin/sudo /usr/bin/ls -la '$RemotePublicDir'"
  )
  if ($removeCanonicalApkCommand) {
    $remotePromoteCommands += $removeCanonicalApkCommand
  }
  $remotePromoteCommand = $remotePromoteCommands -join '; '

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

  Assert-Http200 -Url $downloadUrl -Label 'published'

  Write-Host '==> Publish completed'
  Write-Host "Download URL: $downloadUrl"
  Write-Host "SHA256: $localHash"
} finally {
  Pop-Location
}
