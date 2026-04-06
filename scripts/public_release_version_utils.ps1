Set-StrictMode -Version Latest

function Get-PublicReleaseVersionInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $pubspecPath = Join-Path $RepoRoot 'pubspec.yaml'
  if (-not (Test-Path -LiteralPath $pubspecPath)) {
    throw "pubspec.yaml not found: $pubspecPath"
  }

  $versionLine = @(
    Get-Content -LiteralPath $pubspecPath |
      Where-Object { $_ -match '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$' } |
      Select-Object -First 1
  )
  if ($versionLine.Count -eq 0) {
    throw "Could not parse semantic version from $pubspecPath"
  }

  $match = [regex]::Match(
    $versionLine[0],
    '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$'
  )
  if (-not $match.Success) {
    throw "Could not parse semantic version from line: $($versionLine[0])"
  }

  $displayVersion = $match.Groups[1].Value
  $buildNumber = $match.Groups[2].Value
  $appVersion = if ([string]::IsNullOrWhiteSpace($buildNumber)) {
    $displayVersion
  } else {
    "$displayVersion+$buildNumber"
  }
  return [pscustomobject]@{
    AppVersion     = $appVersion
    DisplayVersion = $displayVersion
    BuildNumber    = $buildNumber
    ReleaseTag     = "v$displayVersion"
    ReleaseName    = "Tutor1on1 v$displayVersion"
  }
}

function Get-PublicReleaseAssetNames {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $versionInfo = Get-PublicReleaseVersionInfo -RepoRoot $RepoRoot
  return [pscustomobject]@{
    VersionInfo        = $versionInfo
    AndroidFileName    = "Tutor1on1-$($versionInfo.DisplayVersion).apk"
    WindowsFileName    = "Tutor1on1-$($versionInfo.DisplayVersion).zip"
    ChecksumsFileName  = 'SHA256SUMS.txt'
    DownloadBaseUrl    = 'https://api.tutor1on1.org/downloads'
  }
}

function Sync-WebsiteReleaseConfig {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $siteJsPath = Join-Path $RepoRoot 'web\site.js'
  if (-not (Test-Path -LiteralPath $siteJsPath)) {
    throw "Website release config not found: $siteJsPath"
  }

  $assetNames = Get-PublicReleaseAssetNames -RepoRoot $RepoRoot
  $versionInfo = $assetNames.VersionInfo
  $originalText = [System.IO.File]::ReadAllText($siteJsPath)
  $normalizedOriginal = $originalText.Replace("`r`n", "`n")
  $updatedText = $normalizedOriginal

  if ($updatedText -notmatch "(?m)^\s*appVersion:\s*'[^']+',\s*$") {
    $updatedText = [regex]::Replace(
      $updatedText,
      "(?m)^(\s*githubRepo:\s*'[^']+',\s*)$",
      "`${1}`n    appVersion: '$($versionInfo.AppVersion)',",
      1
    )
  }
  if ($updatedText -notmatch "(?m)^\s*appVersion:\s*'[^']+',\s*$") {
    throw "Could not inject appVersion into $siteJsPath"
  }

  $updatedText = [regex]::Replace(
    $updatedText,
    "(?m)^(\s*appVersion:\s*')[^']+(',\s*)$",
    "`${1}$($versionInfo.AppVersion)`${2}",
    1
  )
  $updatedText = [regex]::Replace(
    $updatedText,
    "(?m)^(\s*releaseTag:\s*')[^']+(',\s*)$",
    "`${1}$($versionInfo.ReleaseTag)`${2}",
    1
  )
  if ($updatedText -notmatch "(?m)^\s*downloadBaseUrl:\s*'[^']+',\s*$") {
    $updatedText = [regex]::Replace(
      $updatedText,
      "(?m)^(\s*releaseTag:\s*'[^']+',\s*)$",
      "`${1}`n    downloadBaseUrl: '$($assetNames.DownloadBaseUrl)',",
      1
    )
  }
  $updatedText = [regex]::Replace(
    $updatedText,
    "(?m)^(\s*downloadBaseUrl:\s*')[^']+(',\s*)$",
    "`${1}$($assetNames.DownloadBaseUrl)`${2}",
    1
  )
  $updatedText = [regex]::Replace(
    $updatedText,
    "(?m)^(\s*android:\s*')[^']+(',\s*)$",
    "`${1}$($assetNames.AndroidFileName)`${2}",
    1
  )
  $updatedText = [regex]::Replace(
    $updatedText,
    "(?m)^(\s*windows:\s*')[^']+(',\s*)$",
    "`${1}$($assetNames.WindowsFileName)`${2}",
    1
  )

  $changed = -not [string]::Equals(
    $normalizedOriginal,
    $updatedText,
    [System.StringComparison]::Ordinal
  )

  if ($changed) {
    $lineEnding = if ($originalText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $normalizedUpdated = $updatedText.Replace("`n", $lineEnding)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($siteJsPath, $normalizedUpdated, $utf8NoBom)
  }

  return [pscustomobject]@{
    Changed     = $changed
    SiteJsPath  = $siteJsPath
    VersionInfo = $versionInfo
  }
}
