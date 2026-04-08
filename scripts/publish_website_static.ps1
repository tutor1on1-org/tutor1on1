param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$RemoteHost = '43.99.59.107',
  [string]$RemoteUser = 'ecs-user',
  [string]$KeyPath = 'C:\Users\kl\.ssh\id_rsa',
  [string]$LocalWebDir = 'web',
  [string]$RemoteWebsiteDir = '/var/www/tutor1on1_site',
  [string]$SiteBaseUrl = 'https://www.tutor1on1.org'
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

function Resolve-RsyncExe {
  $rsyncCommand = Get-Command rsync -ErrorAction SilentlyContinue
  if ($rsyncCommand) {
    return $rsyncCommand.Source
  }

  $fallbacks = @(
    'C:\Program Files\Git\usr\bin\rsync.exe',
    'C:\msys64\usr\bin\rsync.exe'
  )

  foreach ($candidate in $fallbacks) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  return $null
}

function Convert-ToShellLiteral {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return "'" + ($Value -replace "'", "'\"'\"'") + "'"
}

function Get-RelativeUnixPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BaseDir,
    [Parameter(Mandatory = $true)]
    [string]$FullPath
  )

  return ([System.IO.Path]::GetRelativePath($BaseDir, $FullPath)).Replace('\', '/')
}

function Get-LocalWebsiteManifest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RootDir
  )

  $manifest = @{}
  $files = Get-ChildItem -LiteralPath $RootDir -Recurse -File
  foreach ($file in $files) {
    $relativePath = Get-RelativeUnixPath -BaseDir $RootDir -FullPath $file.FullName
    $manifest[$relativePath] = @{
      FullPath = $file.FullName
      Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  }
  return $manifest
}

function Get-RemoteWebsiteManifest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteUser,
    [Parameter(Mandatory = $true)]
    [string]$RemoteHost,
    [Parameter(Mandatory = $true)]
    [string]$KeyPath,
    [Parameter(Mandatory = $true)]
    [string]$RemoteRootDir
  )

  $manifest = @{}
  $remoteRootLiteral = Convert-ToShellLiteral -Value $RemoteRootDir
  $remoteManifestCommand = @(
    "if [ -d $remoteRootLiteral ]; then",
    "cd $remoteRootLiteral",
    "/usr/bin/find . -type f -print0 | /usr/bin/xargs -0 -r /usr/bin/sha256sum",
    "fi"
  ) -join '; '

  $remoteOutput = & ssh `
    -i $KeyPath `
    -o 'IdentitiesOnly=yes' `
    -o 'BatchMode=yes' `
    -o 'StrictHostKeyChecking=accept-new' `
    "$RemoteUser@$RemoteHost" `
    $remoteManifestCommand
  if ($LASTEXITCODE -ne 0) {
    throw "Remote website manifest failed with exit code $LASTEXITCODE."
  }

  foreach ($line in @($remoteOutput)) {
    $text = "$line".Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
      continue
    }
    if ($text -match '^(?<hash>[0-9a-fA-F]{64})\s+\.\./') {
      continue
    }
    if ($text -match '^(?<hash>[0-9a-fA-F]{64})\s+\./(?<path>.+)$') {
      $manifest[$matches['path']] = $matches['hash'].ToLowerInvariant()
    }
  }

  return $manifest
}

function Sync-WebsiteViaScpIncremental {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LocalRootDir,
    [Parameter(Mandatory = $true)]
    [string]$RemoteUser,
    [Parameter(Mandatory = $true)]
    [string]$RemoteHost,
    [Parameter(Mandatory = $true)]
    [string]$KeyPath,
    [Parameter(Mandatory = $true)]
    [string]$RemoteRootDir
  )

  $localManifest = Get-LocalWebsiteManifest -RootDir $LocalRootDir
  $remoteManifest = Get-RemoteWebsiteManifest `
    -RemoteUser $RemoteUser `
    -RemoteHost $RemoteHost `
    -KeyPath $KeyPath `
    -RemoteRootDir $RemoteRootDir

  $filesToUpload = @()
  foreach ($relativePath in $localManifest.Keys) {
    if (-not $remoteManifest.ContainsKey($relativePath) -or $remoteManifest[$relativePath] -ne $localManifest[$relativePath].Hash) {
      $filesToUpload += $relativePath
    }
  }

  $filesToDelete = @()
  foreach ($relativePath in $remoteManifest.Keys) {
    if (-not $localManifest.ContainsKey($relativePath)) {
      $filesToDelete += $relativePath
    }
  }

  Write-Host "==> Incremental website sync fallback: $($filesToUpload.Count) upload, $($filesToDelete.Count) delete"

  if ($filesToUpload.Count -gt 0) {
    $remoteDirs = $filesToUpload |
      ForEach-Object { [System.IO.Path]::GetDirectoryName($_) } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object { $_.Replace('\', '/') } |
      Sort-Object -Unique

    if ($remoteDirs.Count -gt 0) {
      $mkdirCommands = $remoteDirs | ForEach-Object {
        $remoteDir = "$RemoteRootDir/$_"
        "/usr/bin/mkdir -p $(Convert-ToShellLiteral -Value $remoteDir)"
      }
      $remoteMkdirCommand = $mkdirCommands -join '; '
      $mkdirOutput = & ssh `
        -i $KeyPath `
        -o 'IdentitiesOnly=yes' `
        -o 'BatchMode=yes' `
        -o 'StrictHostKeyChecking=accept-new' `
        "$RemoteUser@$RemoteHost" `
        $remoteMkdirCommand
      if ($LASTEXITCODE -ne 0) {
        throw "Remote website directory creation failed with exit code $LASTEXITCODE."
      }
      $mkdirOutput | ForEach-Object { Write-Host $_ }
    }

    foreach ($relativePath in ($filesToUpload | Sort-Object)) {
      $localFile = $localManifest[$relativePath].FullPath
      $remoteFile = "$RemoteRootDir/$relativePath"
      Write-Host "Upload: $relativePath"
      & scp `
        -i $KeyPath `
        -o 'IdentitiesOnly=yes' `
        -o 'BatchMode=yes' `
        -o 'StrictHostKeyChecking=accept-new' `
        $localFile `
        "${RemoteUser}@${RemoteHost}:$remoteFile"
      if ($LASTEXITCODE -ne 0) {
        throw "scp upload failed for $relativePath with exit code $LASTEXITCODE."
      }
    }
  }

  if ($filesToDelete.Count -gt 0) {
    $deleteCommands = $filesToDelete | Sort-Object | ForEach-Object {
      $remoteFile = "$RemoteRootDir/$_"
      "/usr/bin/rm -f $(Convert-ToShellLiteral -Value $remoteFile)"
    }
    $deleteCommands += "/usr/bin/find $(Convert-ToShellLiteral -Value $RemoteRootDir) -depth -type d -empty -delete"
    $remoteDeleteCommand = $deleteCommands -join '; '
    Write-Host '==> Delete removed remote website files'
    $deleteOutput = & ssh `
      -i $KeyPath `
      -o 'IdentitiesOnly=yes' `
      -o 'BatchMode=yes' `
      -o 'StrictHostKeyChecking=accept-new' `
      "$RemoteUser@$RemoteHost" `
      $remoteDeleteCommand
    if ($LASTEXITCODE -ne 0) {
      throw "Remote website delete failed with exit code $LASTEXITCODE."
    }
    $deleteOutput | ForEach-Object { Write-Host $_ }
  }
}

function Assert-Http200 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url
  )
  $headers = & curl.exe -k -I --max-time 20 --retry 3 --retry-all-errors --retry-delay 2 $Url
  if ($LASTEXITCODE -ne 0) {
    throw "curl header check failed for $Url with exit code $LASTEXITCODE."
  }
  $headers | ForEach-Object { Write-Host $_ }
  if (-not ($headers -match 'HTTP/\d\.\d 200 OK')) {
    throw "URL check failed. Expected HTTP 200: $Url"
  }
}

function Assert-BodyContains {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [string]$LiteralText
  )
  $body = & curl.exe -k --fail --silent --show-error --retry 3 --retry-all-errors --retry-delay 2 $Url
  if ($LASTEXITCODE -ne 0) {
    throw "curl body fetch failed for $Url with exit code $LASTEXITCODE."
  }
  $bodyText = ($body | Out-String)
  $escapedText = [regex]::Escape($LiteralText)
  if (-not ($bodyText | Select-String -Pattern $escapedText -Quiet)) {
    throw "Body verification failed for $Url. Missing text: $LiteralText"
  }
}

function Assert-BodyNotContains {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [string]$LiteralText
  )
  $body = & curl.exe -k --fail --silent --show-error --retry 3 --retry-all-errors --retry-delay 2 $Url
  if ($LASTEXITCODE -ne 0) {
    throw "curl body fetch failed for $Url with exit code $LASTEXITCODE."
  }
  $bodyText = ($body | Out-String)
  $escapedText = [regex]::Escape($LiteralText)
  if ($bodyText | Select-String -Pattern $escapedText -Quiet) {
    throw "Body verification failed for $Url. Unexpected text: $LiteralText"
  }
}

function Assert-NotHttp200 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url
  )
  $headers = & curl.exe -k -I --max-time 20 --retry 3 --retry-all-errors --retry-delay 2 $Url
  if ($LASTEXITCODE -ne 0) {
    throw "curl header check failed for $Url with exit code $LASTEXITCODE."
  }
  $headers | ForEach-Object { Write-Host $_ }
  if ($headers -match 'HTTP/\d\.\d 200 OK') {
    throw "URL unexpectedly returned HTTP 200: $Url"
  }
}

$repoRoot = (Resolve-Path $ProjectRoot).Path
if (-not (Test-Path -LiteralPath $repoRoot)) {
  throw "Project root not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $KeyPath)) {
  throw "SSH key file not found: $KeyPath"
}

$resolvedWebDir = Join-Path $repoRoot $LocalWebDir
if (-not (Test-Path -LiteralPath $resolvedWebDir)) {
  throw "Local web directory not found: $resolvedWebDir"
}

$versionUtilsScript = Join-Path $repoRoot 'scripts\public_release_version_utils.ps1'
if (-not (Test-Path -LiteralPath $versionUtilsScript)) {
  throw "Public release version utils not found: $versionUtilsScript"
}
. $versionUtilsScript
$syncResult = Sync-WebsiteReleaseConfig -RepoRoot $repoRoot
$assetNames = Get-PublicReleaseAssetNames -RepoRoot $repoRoot
if ($syncResult.Changed) {
  Write-Host "==> Synced website release config to $($syncResult.VersionInfo.ReleaseTag) ($($syncResult.VersionInfo.AppVersion))"
} else {
  Write-Host "==> Website release config already matches $($syncResult.VersionInfo.ReleaseTag) ($($syncResult.VersionInfo.AppVersion))"
}

$rsyncExe = Resolve-RsyncExe
$webEntries = Get-ChildItem -LiteralPath $resolvedWebDir -Force
if ($webEntries.Count -eq 0) {
  throw "No website files found under: $resolvedWebDir"
}

Push-Location $repoRoot
try {
  $sshTransport = "ssh -i `"$KeyPath`" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
  $remoteMkdirCommand = "/usr/bin/mkdir -p '$RemoteWebsiteDir'"
  Write-Host '==> Ensure remote website root exists'
  $remoteMkdirOutput = & ssh `
    -i $KeyPath `
    -o 'IdentitiesOnly=yes' `
    -o 'BatchMode=yes' `
    -o 'StrictHostKeyChecking=accept-new' `
    "$RemoteUser@$RemoteHost" `
    $remoteMkdirCommand
  if ($LASTEXITCODE -ne 0) {
    throw "Remote website mkdir failed with exit code $LASTEXITCODE."
  }
  $remoteMkdirOutput | ForEach-Object { Write-Host $_ }

  if ($rsyncExe) {
    Invoke-Checked -Label 'Sync local web directory to remote website root (rsync incremental)' -Action {
      & $rsyncExe `
        '--archive' `
        '--delete' `
        '--compress' `
        '--itemize-changes' `
        '-e' $sshTransport `
        "$resolvedWebDir/" `
        "${RemoteUser}@${RemoteHost}:$RemoteWebsiteDir/"
    }
  } else {
    Write-Host '==> rsync not found; fallback to native SSH/SCP incremental sync'
    Sync-WebsiteViaScpIncremental `
      -LocalRootDir $resolvedWebDir `
      -RemoteUser $RemoteUser `
      -RemoteHost $RemoteHost `
      -KeyPath $KeyPath `
      -RemoteRootDir $RemoteWebsiteDir
  }

  $remoteVerifyCommand = @(
    "/usr/bin/ls -la '$RemoteWebsiteDir'",
    "/usr/bin/find '$RemoteWebsiteDir' -maxdepth 3 -type f | /usr/bin/sort"
  ) -join '; '

  Write-Host '==> Verify remote website tree'
  $remoteOutput = & ssh `
    -i $KeyPath `
    -o 'IdentitiesOnly=yes' `
    -o 'BatchMode=yes' `
    -o 'StrictHostKeyChecking=accept-new' `
    "$RemoteUser@$RemoteHost" `
    $remoteVerifyCommand
  if ($LASTEXITCODE -ne 0) {
    throw "Remote website verification failed with exit code $LASTEXITCODE."
  }
  $remoteOutput | ForEach-Object { Write-Host $_ }

  $http200Paths = @(
    '/',
    '/help/',
    '/install/',
    '/install/android/',
    '/install/windows/',
    '/zh/',
    '/zh/help/',
    '/zh/install/',
    '/zh/install/android/',
    '/zh/install/windows/',
    '/zh-tw/',
    '/zh-tw/help/',
    '/zh-tw/install/',
    '/zh-tw/install/android/',
    '/zh-tw/install/windows/',
    '/ja/',
    '/ja/help/',
    '/ja/install/',
    '/ja/install/android/',
    '/ja/install/windows/',
    '/ko/',
    '/ko/help/',
    '/ko/install/',
    '/ko/install/android/',
    '/ko/install/windows/',
    '/es/',
    '/es/help/',
    '/es/install/',
    '/es/install/android/',
    '/es/install/windows/',
    '/fr/',
    '/fr/help/',
    '/fr/install/',
    '/fr/install/android/',
    '/fr/install/windows/',
    '/de/',
    '/de/help/',
    '/de/install/',
    '/de/install/android/',
    '/de/install/windows/'
  )
  foreach ($path in $http200Paths) {
    $url = "$($SiteBaseUrl.TrimEnd('/'))$path"
    Write-Host "==> Verify page: $url"
    Assert-Http200 -Url $url
  }

  $bodyChecks = @(
    @{ Path = '/install/'; LiteralText = 'api.tutor1on1.org/downloads/' },
    @{ Path = '/zh/install/'; LiteralText = 'api.tutor1on1.org/downloads/' }
  )
  foreach ($check in $bodyChecks) {
    $url = "$($SiteBaseUrl.TrimEnd('/'))$($check.Path)"
    Write-Host "==> Verify page content: $url"
    Assert-BodyContains -Url $url -LiteralText $check.LiteralText
  }

  $siteScriptChecks = @(
    $assetNames.AndroidFileName,
    $assetNames.WindowsFileName
  )
  foreach ($literalText in $siteScriptChecks) {
    $url = "$($SiteBaseUrl.TrimEnd('/'))/site.js"
    Write-Host "==> Verify site.js content: $url"
    Assert-BodyContains -Url $url -LiteralText $literalText
  }

  $bodyAbsenceChecks = @(
    '/install/',
    '/zh/install/',
    '/zh-tw/install/',
    '/ja/install/',
    '/ko/install/',
    '/es/install/',
    '/fr/install/',
    '/de/install/'
  )
  foreach ($path in $bodyAbsenceChecks) {
    $url = "$($SiteBaseUrl.TrimEnd('/'))$path"
    Write-Host "==> Verify page does not mention macOS: $url"
    Assert-BodyNotContains -Url $url -LiteralText 'macOS'
    Assert-BodyNotContains -Url $url -LiteralText '/install/macos/'
  }

  $removedPaths = @(
    '/install/macos/',
    '/zh/install/macos/',
    '/zh-tw/install/macos/',
    '/ja/install/macos/',
    '/ko/install/macos/',
    '/es/install/macos/',
    '/fr/install/macos/',
    '/de/install/macos/'
  )
  foreach ($path in $removedPaths) {
    $url = "$($SiteBaseUrl.TrimEnd('/'))$path"
    Write-Host "==> Verify removed page is not publicly available: $url"
    Assert-NotHttp200 -Url $url
  }

  Write-Host '==> Website publish completed'
} finally {
  Pop-Location
}
