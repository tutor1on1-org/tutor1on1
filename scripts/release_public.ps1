param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$CommitMessage = 'Public release update',
  [switch]$SkipValidation,
  [bool]$AutoBumpVersion = $true,
  [switch]$SkipGit,
  [switch]$SkipAndroid,
  [switch]$SkipAndroidBuild,
  [switch]$SkipWindows,
  [switch]$SkipWindowsBuild,
  [switch]$SkipGitHubRelease,
  [switch]$SkipAnalyze,
  [switch]$SkipFlutterTests,
  [switch]$SkipPush,
  [switch]$SkipPromptAssetTests,
  [switch]$SkipZipValidation,
  [switch]$SkipWebsite
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

function Get-GitStatusLines {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )
  $statusLines = & git -C $RepoRoot status --short
  if ($LASTEXITCODE -ne 0) {
    throw "git status failed with exit code $LASTEXITCODE."
  }
  return ,@($statusLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-PubspecVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )
  $pubspecPath = Join-Path $RepoRoot 'pubspec.yaml'
  if (-not (Test-Path -LiteralPath $pubspecPath)) {
    throw "pubspec.yaml not found: $pubspecPath"
  }
  $versionLine = Get-Content -LiteralPath $pubspecPath |
    Where-Object { $_ -match '^version:\s*[0-9]+\.[0-9]+\.[0-9]+' } |
    Select-Object -First 1
  if (-not $versionLine) {
    throw 'Could not read version from pubspec.yaml'
  }
  return $versionLine.Replace('version:', '').Trim()
}

function Get-NextPatchVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Version
  )
  $match = [regex]::Match($Version, '^([0-9]+)\.([0-9]+)\.([0-9]+)(\+[^ ]+)?$')
  if (-not $match.Success) {
    throw "Unsupported version format: $Version"
  }
  $major = [int]$match.Groups[1].Value
  $minor = [int]$match.Groups[2].Value
  $patch = [int]$match.Groups[3].Value + 1
  $suffix = "$($match.Groups[4].Value)"
  return "$major.$minor.$patch$suffix"
}

function Set-PubspecVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$Version
  )
  $pubspecPath = Join-Path $RepoRoot 'pubspec.yaml'
  $updatedLines = @(
    Get-Content -LiteralPath $pubspecPath |
      ForEach-Object {
        if ($_ -match '^\s*version:\s*[0-9]+\.[0-9]+\.[0-9]+(\+[^ ]+)?\s*$') {
          "version: $Version"
        } else {
          $_
        }
      }
  )
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText(
    $pubspecPath,
    ($updatedLines -join [Environment]::NewLine),
    $utf8NoBom
  )
}

function Get-RequiredGitHubRemote {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $remoteLines = @(& git -C $RepoRoot remote)
  if ($LASTEXITCODE -ne 0) {
    throw "git remote failed with exit code $LASTEXITCODE."
  }
  if ($remoteLines -notcontains 'github') {
    throw "Required GitHub remote 'github' is missing."
  }
  return 'github'
}

function Get-CurrentBranchName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $branchName = ((& git -C $RepoRoot rev-parse --abbrev-ref HEAD) | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0) {
    throw "git rev-parse --abbrev-ref HEAD failed with exit code $LASTEXITCODE."
  }
  $normalized = "$branchName".Trim()
  if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -eq 'HEAD') {
    throw 'Release push requires a named local branch, not a detached HEAD.'
  }
  return $normalized
}

function Ensure-LocalReleaseTagAtHead {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag
  )

  $headCommit = ((& git -C $RepoRoot rev-parse HEAD) | Select-Object -First 1).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "git rev-parse HEAD failed with exit code $LASTEXITCODE."
  }

  $tagList = @(& git -C $RepoRoot tag --list $ReleaseTag)
  if ($LASTEXITCODE -ne 0) {
    throw "git tag --list $ReleaseTag failed with exit code $LASTEXITCODE."
  }
  if ($tagList.Count -eq 0 -or [string]::IsNullOrWhiteSpace("$($tagList[0])")) {
    Invoke-Checked -Label "git tag $ReleaseTag" -Action {
      git -C $RepoRoot tag $ReleaseTag
    }
    return
  }

  $tagCommitLines = @(& git -C $RepoRoot rev-list -n 1 "refs/tags/$ReleaseTag")
  if ($LASTEXITCODE -ne 0 -or $tagCommitLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace("$($tagCommitLines[0])")) {
    throw "git rev-list refs/tags/$ReleaseTag failed with exit code $LASTEXITCODE."
  }

  $tagCommit = "$($tagCommitLines[0])".Trim()
  if ($tagCommit -ne $headCommit) {
    throw "Local tag $ReleaseTag points to $tagCommit instead of HEAD $headCommit."
  }
}

$repoRoot = (Resolve-Path $ProjectRoot).Path
if (-not (Test-Path -LiteralPath $repoRoot)) {
  throw "Project root not found: $ProjectRoot"
}

$validateScript = Join-Path $repoRoot 'scripts\validate_project.ps1'
$versionUtilsScript = Join-Path $repoRoot 'scripts\public_release_version_utils.ps1'
$androidPublishScript = Join-Path $repoRoot 'scripts\publish_android_release.ps1'
$windowsPublishScript = Join-Path $repoRoot 'skills\windows_release_publish\scripts\publish_windows_release.ps1'
$githubReleaseScript = Join-Path $repoRoot 'public_release\publish_github_release.ps1'
$websitePublishScript = Join-Path $repoRoot 'scripts\publish_website_static.ps1'

Push-Location $repoRoot
try {
  if (-not (Test-Path -LiteralPath $versionUtilsScript)) {
    throw "Public release version utils not found: $versionUtilsScript"
  }
  . $versionUtilsScript

  if (-not $SkipGit.IsPresent -and $AutoBumpVersion) {
    $currentVersion = Get-PubspecVersion -RepoRoot $repoRoot
    $nextVersion = Get-NextPatchVersion -Version $currentVersion
    Set-PubspecVersion -RepoRoot $repoRoot -Version $nextVersion
    Write-Host "==> Auto-bumped version from $currentVersion to $nextVersion"
  }

  $syncResult = Sync-WebsiteReleaseConfig -RepoRoot $repoRoot
  $versionInfo = $syncResult.VersionInfo
  if ($syncResult.Changed) {
    Write-Host "==> Synced website release config to $($syncResult.VersionInfo.ReleaseTag) ($($syncResult.VersionInfo.AppVersion))"
  } else {
    Write-Host "==> Website release config already matches $($syncResult.VersionInfo.ReleaseTag) ($($syncResult.VersionInfo.AppVersion))"
  }

  if (-not $SkipValidation.IsPresent) {
    Invoke-Checked -Label 'Validate project' -Action {
      powershell -ExecutionPolicy Bypass -File $validateScript -NoPostHook -SkipAnalyze:$SkipAnalyze -SkipFlutterTest:$SkipFlutterTests
    }
  } else {
    Write-Host '==> Skip validation requested'
  }

  if (-not $SkipGit.IsPresent) {
    $gitRemote = Get-RequiredGitHubRemote -RepoRoot $repoRoot
    $branchName = Get-CurrentBranchName -RepoRoot $repoRoot
    $statusLines = Get-GitStatusLines -RepoRoot $repoRoot
    if ($statusLines.Count -gt 0) {
      Write-Host '==> Git changes detected'
      $statusLines | ForEach-Object { Write-Host $_ }

      Invoke-Checked -Label 'git add -A' -Action {
        git -C $repoRoot add -A
      }
      Invoke-Checked -Label "git commit -m `"$CommitMessage`"" -Action {
        git -C $repoRoot commit -m $CommitMessage
      }
    } else {
      Write-Host '==> Git worktree already clean; skip commit'
    }

    Ensure-LocalReleaseTagAtHead -RepoRoot $repoRoot -ReleaseTag $versionInfo.ReleaseTag

    if (-not $SkipPush.IsPresent) {
      Invoke-Checked -Label "git push $gitRemote $branchName" -Action {
        git -C $repoRoot push $gitRemote "HEAD:refs/heads/$branchName"
      }
      Invoke-Checked -Label "git push $gitRemote $($versionInfo.ReleaseTag)" -Action {
        git -C $repoRoot push $gitRemote "refs/tags/$($versionInfo.ReleaseTag)"
      }
    } else {
      Write-Host '==> Skip git push requested'
    }
  } else {
    Write-Host '==> Skip git requested'
  }

  if (-not $SkipAndroid.IsPresent) {
    $androidArgs = @(
      '-ExecutionPolicy', 'Bypass',
      '-File', $androidPublishScript
    )
    if (-not $SkipValidation.IsPresent) {
      $androidArgs += '-SkipPubGet'
    }
    if ($SkipAndroidBuild.IsPresent) {
      $androidArgs += '-SkipBuild'
    }
    Invoke-Checked -Label 'Publish Android release' -Action {
      powershell @androidArgs
    }
  } else {
    Write-Host '==> Skip Android publish requested'
  }

  if (-not $SkipWindows.IsPresent) {
    $windowsArgs = @(
      '-ExecutionPolicy', 'Bypass',
      '-File', $windowsPublishScript
    )
    if ($SkipWindowsBuild.IsPresent) {
      $windowsArgs += '-SkipBuild'
    }
    if ($SkipPromptAssetTests.IsPresent) {
      $windowsArgs += '-SkipPromptAssetTests'
    }
    if ($SkipZipValidation.IsPresent) {
      $windowsArgs += '-SkipZipValidation'
    }
    Invoke-Checked -Label 'Publish Windows release' -Action {
      powershell @windowsArgs
    }
  } else {
    Write-Host '==> Skip Windows publish requested'
  }

  if (-not $SkipGitHubRelease.IsPresent) {
    $githubArgs = @(
      '-ExecutionPolicy', 'Bypass',
      '-File', $githubReleaseScript,
      '-SkipPubGet',
      '-SkipAnalyze',
      '-SkipTest',
      '-SkipAndroidBuild',
      '-SkipWindowsBuild'
    )
    Invoke-Checked -Label 'Publish GitHub release assets' -Action {
      powershell @githubArgs
    }
  } else {
    Write-Host '==> Skip GitHub release publish requested'
  }

  if (-not $SkipWebsite.IsPresent) {
    Invoke-Checked -Label 'Publish website static files' -Action {
      powershell -ExecutionPolicy Bypass -File $websitePublishScript
    }
  } else {
    Write-Host '==> Skip website publish requested'
  }

  Write-Host '==> Public release flow completed'
} finally {
  Pop-Location
}
