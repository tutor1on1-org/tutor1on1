param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$CommitMessage = 'Public release update',
  [switch]$SkipValidation,
  [switch]$SkipGit,
  [switch]$SkipAndroid,
  [switch]$SkipAndroidBuild,
  [switch]$SkipWindows,
  [switch]$SkipWindowsBuild,
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
  return @($statusLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$repoRoot = (Resolve-Path $ProjectRoot).Path
if (-not (Test-Path -LiteralPath $repoRoot)) {
  throw "Project root not found: $ProjectRoot"
}

$validateScript = Join-Path $repoRoot 'scripts\validate_project.ps1'
$androidPublishScript = Join-Path $repoRoot 'scripts\publish_android_release.ps1'
$windowsPublishScript = Join-Path $repoRoot 'skills\windows_release_publish\scripts\publish_windows_release.ps1'
$websitePublishScript = Join-Path $repoRoot 'scripts\publish_website_static.ps1'

Push-Location $repoRoot
try {
  if (-not $SkipValidation.IsPresent) {
    Invoke-Checked -Label 'Validate project' -Action {
      powershell -ExecutionPolicy Bypass -File $validateScript -NoPostHook
    }
  } else {
    Write-Host '==> Skip validation requested'
  }

  if (-not $SkipGit.IsPresent) {
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
      Invoke-Checked -Label 'git push' -Action {
        git -C $repoRoot push
      }
    } else {
      Write-Host '==> Git worktree already clean; skip commit/push'
    }
  } else {
    Write-Host '==> Skip git requested'
  }

  if (-not $SkipAndroid.IsPresent) {
    $androidArgs = @(
      '-ExecutionPolicy', 'Bypass',
      '-File', $androidPublishScript
    )
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
