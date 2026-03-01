param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
  [string]$RemoteHost = '43.99.59.107',
  [string]$RemoteUser = 'ecs-user',
  [string]$KeyPath = 'C:\Users\kl\.ssh\id_rsa',
  [string]$RemotePublicDir = '/var/lib/family_teacher_remote/public',
  [string]$DownloadBaseUrl = 'https://43.99.59.107/downloads',
  [string]$ZipName = 'family_teacher.zip',
  [switch]$SkipBuild,
  [switch]$SkipUpload
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
if (-not (Test-Path -LiteralPath $repoRoot)) {
  throw "Project root not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $KeyPath)) {
  throw "SSH key file not found: $KeyPath"
}

$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$zipPath = Join-Path $repoRoot ("build\" + $ZipName)
$downloadUrl = "$($DownloadBaseUrl.TrimEnd('/'))/$ZipName"
$tmpRemoteZip = "/tmp/$ZipName"
$zipBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ZipName)
$cleanupPattern = "$zipBaseName*.zip"

Push-Location $repoRoot
try {
  if (-not $SkipBuild.IsPresent) {
    Invoke-Checked -Label 'flutter build windows --release' -Action {
      flutter build windows --release
    }
  } else {
    Write-Host '==> Skip build requested'
  }

  if (-not (Test-Path -LiteralPath $releaseDir)) {
    throw "Release directory not found: $releaseDir"
  }

  if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
  }
  Invoke-Checked -Label "Create ZIP: $zipPath" -Action {
    tar -a -c -f $zipPath -C $releaseDir .
  }

  $zipItem = Get-Item -LiteralPath $zipPath
  if ($zipItem.Length -le 0) {
    throw "ZIP file is empty: $zipPath"
  }
  $localHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Host "Local ZIP size: $($zipItem.Length) bytes"
  Write-Host "Local SHA256: $localHash"

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

  $remoteCommand = @(
    "/usr/bin/ls -la '$tmpRemoteZip'",
    "/usr/bin/sudo /usr/bin/install -m 0644 -o root -g root '$tmpRemoteZip' '$RemotePublicDir/$ZipName'",
    "/usr/bin/sudo /usr/bin/find '$RemotePublicDir' -maxdepth 1 -type f -name '$cleanupPattern' ! -name '$ZipName' -print -delete",
    "/usr/bin/sudo /usr/bin/sha256sum '$RemotePublicDir/$ZipName'",
    "/usr/bin/sudo /usr/bin/ls -la '$RemotePublicDir'",
    "/usr/bin/rm -f '$tmpRemoteZip'"
  ) -join '; '

  Write-Host '==> Install on remote + cleanup old ZIPs'
  $remoteOutput = & ssh `
    -i $KeyPath `
    -o 'IdentitiesOnly=yes' `
    -o 'BatchMode=yes' `
    -o 'StrictHostKeyChecking=accept-new' `
    "$RemoteUser@$RemoteHost" `
    $remoteCommand
  if ($LASTEXITCODE -ne 0) {
    throw "Remote install command failed with exit code $LASTEXITCODE."
  }
  $remoteOutput | ForEach-Object { Write-Host $_ }

  $remoteHashMatch = ($remoteOutput | Select-String -Pattern '(?<hash>[0-9a-fA-F]{64})\s+.+').Matches | Select-Object -First 1
  if ($null -eq $remoteHashMatch) {
    throw 'Could not parse remote SHA256 output.'
  }
  $remoteHash = $remoteHashMatch.Groups['hash'].Value.ToLowerInvariant()
  if ($remoteHash -ne $localHash) {
    throw "SHA256 mismatch. local=$localHash remote=$remoteHash"
  }
  Write-Host "Remote SHA256 matches local: $remoteHash"

  Write-Host "==> Verify download URL: $downloadUrl"
  $headers = & curl.exe -k -I --max-time 20 $downloadUrl
  if ($LASTEXITCODE -ne 0) {
    throw "curl header check failed with exit code $LASTEXITCODE."
  }
  $headers | ForEach-Object { Write-Host $_ }
  if (-not ($headers -match 'HTTP/1\.1 200 OK')) {
    throw "Download URL check failed. Expected HTTP 200 for $downloadUrl"
  }

  Write-Host '==> Publish completed'
  Write-Host "Download URL: $downloadUrl"
  Write-Host "SHA256: $localHash"
} finally {
  Pop-Location
}
