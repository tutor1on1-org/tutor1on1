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

function Get-PublicWebReleaseInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $versionInfo = Get-PublicReleaseVersionInfo -RepoRoot $RepoRoot
  return [pscustomobject]@{
    VersionInfo = $versionInfo
    AppUrl      = 'https://www.tutor1on1.org/app/'
  }
}

function Write-PublicReleaseTextIfChanged {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$OriginalText,
    [Parameter(Mandatory = $true)]
    [string]$UpdatedText
  )

  $normalizedOriginal = $OriginalText.Replace("`r`n", "`n")
  $normalizedUpdated = $UpdatedText.Replace("`r`n", "`n")
  if ([string]::Equals(
      $normalizedOriginal,
      $normalizedUpdated,
      [System.StringComparison]::Ordinal
    )) {
    return $false
  }

  $lineEnding = if ($OriginalText.Contains("`r`n")) { "`r`n" } else { "`n" }
  $textToWrite = $normalizedUpdated.Replace("`n", $lineEnding)
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $textToWrite, $utf8NoBom)
  return $true
}

function Get-PublicReleaseDocumentPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $publicReadmePath = Join-Path $RepoRoot 'PUBLIC_CLIENT_README.md'
  if (-not (Test-Path -LiteralPath $publicReadmePath)) {
    $publicReadmePath = Join-Path $RepoRoot 'README.md'
  }
  return @(
    $publicReadmePath,
    (Join-Path $RepoRoot 'VERSIONING.md')
  )
}

function Get-PublicReleaseDocumentRules {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [pscustomobject]$VersionInfo
  )

  if ([System.IO.Path]::GetFileName($Path) -eq 'VERSIONING.md') {
    return @(
      [pscustomobject]@{
        Name = 'current release tag'
        Pattern = '(?m)(?<=^- Git tag: `)v[0-9]+\.[0-9]+\.[0-9]+(?=`\s*$)'
        Expected = $VersionInfo.ReleaseTag
      },
      [pscustomobject]@{
        Name = 'current app version'
        Pattern = '(?m)(?<=^- App version: `)[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?(?=`\s*$)'
        Expected = $VersionInfo.AppVersion
      }
    )
  }

  return @(
    [pscustomobject]@{
      Name = 'current public release tag'
      Pattern = '(?m)(?<=^- Current public release tag: `)v[0-9]+\.[0-9]+\.[0-9]+(?=`\s*$)'
      Expected = $VersionInfo.ReleaseTag
    },
    [pscustomobject]@{
      Name = 'current pubspec version'
      Pattern = '(?m)(?<=^- App version in `pubspec\.yaml`: `)[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?(?=`\s*$)'
      Expected = $VersionInfo.AppVersion
    }
  )
}

function Sync-PublicReleaseDocumentVersions {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [pscustomobject]$VersionInfo
  )

  $changedPaths = @()
  $documentPaths = @(Get-PublicReleaseDocumentPaths -RepoRoot $RepoRoot)
  foreach ($documentPath in $documentPaths) {
    if (-not (Test-Path -LiteralPath $documentPath)) {
      throw "Public release document not found: $documentPath"
    }

    $originalText = [System.IO.File]::ReadAllText($documentPath)
    $updatedText = $originalText
    $rules = @(Get-PublicReleaseDocumentRules `
        -Path $documentPath `
        -VersionInfo $VersionInfo)
    foreach ($rule in $rules) {
      $matches = [regex]::Matches($updatedText, $rule.Pattern)
      if ($matches.Count -eq 0) {
        throw "Missing $($rule.Name) marker in $documentPath"
      }
      $updatedText = [regex]::Replace(
        $updatedText,
        $rule.Pattern,
        $rule.Expected
      )
    }

    if (Write-PublicReleaseTextIfChanged `
      -Path $documentPath `
      -OriginalText $originalText `
      -UpdatedText $updatedText) {
      $changedPaths += $documentPath
    }
  }

  return $changedPaths
}

function Sync-WebsiteReleaseConfig {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $siteJsPath = Join-Path $RepoRoot 'website\site.js'
  if (-not (Test-Path -LiteralPath $siteJsPath)) {
    throw "Website release config not found: $siteJsPath"
  }
  $webRoot = Join-Path $RepoRoot 'website'
  if (-not (Test-Path -LiteralPath $webRoot)) {
    throw "Website root not found: $webRoot"
  }

  $webRelease = Get-PublicWebReleaseInfo -RepoRoot $RepoRoot
  $versionInfo = $webRelease.VersionInfo
  $documentChangedPaths = @(
    Sync-PublicReleaseDocumentVersions `
      -RepoRoot $RepoRoot `
      -VersionInfo $versionInfo
  )
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
  if ($updatedText -notmatch "(?m)^\s*appUrl:\s*'[^']+',\s*$") {
    $updatedText = [regex]::Replace(
      $updatedText,
      "(?m)^(\s*releaseTag:\s*'[^']+',\s*)$",
      "`${1}`n    appUrl: '$($webRelease.AppUrl)',",
      1
    )
  }
  $updatedText = [regex]::Replace(
    $updatedText,
    "(?m)^(\s*appUrl:\s*')[^']+(',\s*)$",
    "`${1}$($webRelease.AppUrl)`${2}",
    1
  )

  $changed = -not [string]::Equals(
    $normalizedOriginal,
    $updatedText,
    [System.StringComparison]::Ordinal
  )

  $htmlChanged = $false
  $htmlFiles = Get-ChildItem -LiteralPath $webRoot -Recurse -File -Filter 'index.html'
  foreach ($htmlFile in $htmlFiles) {
    $htmlOriginal = [System.IO.File]::ReadAllText($htmlFile.FullName)
    $htmlNormalized = $htmlOriginal.Replace("`r`n", "`n")
    $htmlUpdated = $htmlNormalized
    # Single-source the displayed version: rewrite the inner text of the
    # data-release-version / data-release-tag elements so no-JS / curl / SEO
    # never drift from site.js. The JS metadata becomes a redundant fallback.
    $htmlUpdated = [regex]::Replace(
      $htmlUpdated,
      '(data-release-version[^>]*>)[^<]*(<)',
      "`${1}$($versionInfo.AppVersion)`${2}"
    )
    $htmlUpdated = [regex]::Replace(
      $htmlUpdated,
      '(data-release-tag[^>]*>)[^<]*(<)',
      "`${1}$($versionInfo.ReleaseTag)`${2}"
    )

    if (-not [string]::Equals($htmlNormalized, $htmlUpdated, [System.StringComparison]::Ordinal)) {
      $htmlChanged = $true
      [void](Write-PublicReleaseTextIfChanged `
        -Path $htmlFile.FullName `
        -OriginalText $htmlOriginal `
        -UpdatedText $htmlUpdated)
    }
  }

  if ($changed) {
    [void](Write-PublicReleaseTextIfChanged `
      -Path $siteJsPath `
      -OriginalText $originalText `
      -UpdatedText $updatedText)
  }

  $validationResult = Assert-PublicReleaseVersionMetadata -RepoRoot $RepoRoot
  return [pscustomobject]@{
    Changed              = (
      $changed -or
      $htmlChanged -or
      $documentChangedPaths.Count -gt 0
    )
    SiteJsPath           = $siteJsPath
    DocumentChangedPaths = $documentChangedPaths
    ValidationResult     = $validationResult
    VersionInfo          = $versionInfo
  }
}

function Assert-PublicReleaseVersionMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $webRelease = Get-PublicWebReleaseInfo -RepoRoot $RepoRoot
  $versionInfo = $webRelease.VersionInfo
  $siteJsPath = Join-Path $RepoRoot 'website\site.js'
  $webRoot = Join-Path $RepoRoot 'website'
  if (-not (Test-Path -LiteralPath $siteJsPath)) {
    throw "Website release config not found: $siteJsPath"
  }

  $siteJsText = [System.IO.File]::ReadAllText($siteJsPath)
  $siteAssignments = @(
    @{
      Name = 'appVersion'
      Pattern = "(?m)^\s*appVersion:\s*'([^']+)',\s*$"
      Expected = $versionInfo.AppVersion
    },
    @{
      Name = 'releaseTag'
      Pattern = "(?m)^\s*releaseTag:\s*'([^']+)',\s*$"
      Expected = $versionInfo.ReleaseTag
    },
    @{
      Name = 'web app URL'
      Pattern = "(?m)^\s*appUrl:\s*'([^']+)',\s*$"
      Expected = $webRelease.AppUrl
    }
  )
  foreach ($assignment in $siteAssignments) {
    $matches = [regex]::Matches($siteJsText, $assignment.Pattern)
    if ($matches.Count -ne 1) {
      throw "Expected exactly one $($assignment.Name) assignment in $siteJsPath; found $($matches.Count)."
    }
    if ($matches[0].Groups[1].Value -cne $assignment.Expected) {
      throw "$($assignment.Name) in $siteJsPath is '$($matches[0].Groups[1].Value)'; expected '$($assignment.Expected)'."
    }
  }

  $htmlFiles = @(Get-ChildItem -LiteralPath $webRoot -Recurse -File -Filter '*.html')
  if ($htmlFiles.Count -eq 0) {
    throw "No website HTML files found under: $webRoot"
  }

  $releaseVersionMarkerCount = 0
  $releaseTagMarkerCount = 0
  foreach ($htmlFile in $htmlFiles) {
    $htmlText = [System.IO.File]::ReadAllText($htmlFile.FullName)
    $versionMatches = [regex]::Matches(
      $htmlText,
      'data-release-version\b[^>]*>\s*([^<]*)<',
      [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    foreach ($versionMatch in $versionMatches) {
      $releaseVersionMarkerCount++
      if ($versionMatch.Groups[1].Value.Trim() -cne $versionInfo.AppVersion) {
        throw "Release version marker in $($htmlFile.FullName) is '$($versionMatch.Groups[1].Value.Trim())'; expected '$($versionInfo.AppVersion)'."
      }
    }

    $tagMatches = [regex]::Matches(
      $htmlText,
      'data-release-tag\b[^>]*>\s*([^<]*)<',
      [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    foreach ($tagMatch in $tagMatches) {
      $releaseTagMarkerCount++
      if ($tagMatch.Groups[1].Value.Trim() -cne $versionInfo.ReleaseTag) {
        throw "Release tag marker in $($htmlFile.FullName) is '$($tagMatch.Groups[1].Value.Trim())'; expected '$($versionInfo.ReleaseTag)'."
      }
    }
  }
  if ($releaseVersionMarkerCount -eq 0) {
    throw "No data-release-version markers found under: $webRoot"
  }
  if ($releaseTagMarkerCount -eq 0) {
    throw "No data-release-tag markers found under: $webRoot"
  }

  $documentPaths = @(Get-PublicReleaseDocumentPaths -RepoRoot $RepoRoot)
  foreach ($documentPath in $documentPaths) {
    if (-not (Test-Path -LiteralPath $documentPath)) {
      throw "Public release document not found: $documentPath"
    }
    $documentText = [System.IO.File]::ReadAllText($documentPath)
    $rules = @(Get-PublicReleaseDocumentRules `
        -Path $documentPath `
        -VersionInfo $versionInfo)
    foreach ($rule in $rules) {
      $matches = [regex]::Matches($documentText, $rule.Pattern)
      if ($matches.Count -eq 0) {
        throw "Missing $($rule.Name) marker in $documentPath"
      }
      foreach ($match in $matches) {
        if ($match.Value -cne $rule.Expected) {
          throw "$($rule.Name) '$($match.Value)' in $documentPath does not match '$($rule.Expected)'."
        }
      }
    }
  }

  return [pscustomobject]@{
    VersionInfo              = $versionInfo
    HtmlFileCount            = $htmlFiles.Count
    ReleaseVersionMarkerCount = $releaseVersionMarkerCount
    ReleaseTagMarkerCount    = $releaseTagMarkerCount
  }
}
