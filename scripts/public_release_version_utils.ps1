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
  $webRoot = Join-Path $RepoRoot 'web'
  if (-not (Test-Path -LiteralPath $webRoot)) {
    throw "Website root not found: $webRoot"
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

  $downloadReferenceChanged = $false
  $htmlFiles = Get-ChildItem -LiteralPath $webRoot -Recurse -File -Filter 'index.html'
  foreach ($htmlFile in $htmlFiles) {
    $htmlOriginal = [System.IO.File]::ReadAllText($htmlFile.FullName)
    $htmlNormalized = $htmlOriginal.Replace("`r`n", "`n")
    $htmlUpdated = $htmlNormalized
    $htmlUpdated = $htmlUpdated.Replace(
      'https://api.tutor1on1.org/downloads/Tutor1on1.apk',
      "$($assetNames.DownloadBaseUrl)/$($assetNames.AndroidFileName)"
    )
    $htmlUpdated = $htmlUpdated.Replace(
      'https://api.tutor1on1.org/downloads/Tutor1on1.zip',
      "$($assetNames.DownloadBaseUrl)/$($assetNames.WindowsFileName)"
    )
    $htmlUpdated = $htmlUpdated.Replace(
      'Tutor1on1.apk',
      $assetNames.AndroidFileName
    )
    $htmlUpdated = $htmlUpdated.Replace(
      'Tutor1on1.zip',
      $assetNames.WindowsFileName
    )
    $htmlUpdated = [regex]::Replace(
      $htmlUpdated,
      'https://api\.tutor1on1\.org/downloads/Tutor1on1(?:-[0-9]+\.[0-9]+\.[0-9]+)?\.apk',
      "$($assetNames.DownloadBaseUrl)/$($assetNames.AndroidFileName)"
    )
    $htmlUpdated = [regex]::Replace(
      $htmlUpdated,
      'https://api\.tutor1on1\.org/downloads/Tutor1on1(?:-[0-9]+\.[0-9]+\.[0-9]+)?\.zip',
      "$($assetNames.DownloadBaseUrl)/$($assetNames.WindowsFileName)"
    )
    $htmlUpdated = [regex]::Replace(
      $htmlUpdated,
      '\bTutor1on1(?:-[0-9]+\.[0-9]+\.[0-9]+)?\.apk\b',
      $assetNames.AndroidFileName
    )
    $htmlUpdated = [regex]::Replace(
      $htmlUpdated,
      '\bTutor1on1(?:-[0-9]+\.[0-9]+\.[0-9]+)?\.zip\b',
      $assetNames.WindowsFileName
    )

    if (-not [string]::Equals($htmlNormalized, $htmlUpdated, [System.StringComparison]::Ordinal)) {
      $downloadReferenceChanged = $true
      $lineEnding = if ($htmlOriginal.Contains("`r`n")) { "`r`n" } else { "`n" }
      $normalizedUpdatedHtml = $htmlUpdated.Replace("`n", $lineEnding)
      $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
      [System.IO.File]::WriteAllText($htmlFile.FullName, $normalizedUpdatedHtml, $utf8NoBom)
    }
  }

  if ($changed) {
    $lineEnding = if ($originalText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $normalizedUpdated = $updatedText.Replace("`n", $lineEnding)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($siteJsPath, $normalizedUpdated, $utf8NoBom)
  }

  return [pscustomobject]@{
    Changed     = ($changed -or $downloadReferenceChanged)
    SiteJsPath  = $siteJsPath
    VersionInfo = $versionInfo
  }
}
