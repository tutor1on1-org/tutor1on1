param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$RepoSlug = 'tutor1on1-org/tutor1on1',
  [string]$ReleaseTag,
  [string]$ReleaseName,
  [switch]$SkipPackage,
  [switch]$SkipPubGet,
  [switch]$SkipAnalyze,
  [switch]$SkipTest,
  [switch]$SkipAndroidBuild,
  [switch]$SkipWindowsBuild
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

function Get-GitHubToken {
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    return $env:GITHUB_TOKEN.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    return $env:GH_TOKEN.Trim()
  }

  $credentialInput = "protocol=https`nhost=github.com`n`n"
  $credentialOutput = $credentialInput | git credential fill
  if ($LASTEXITCODE -ne 0) {
    throw "git credential fill failed with exit code $LASTEXITCODE."
  }

  $passwordLine = @($credentialOutput | Where-Object { $_ -like 'password=*' } | Select-Object -First 1)
  if ($passwordLine.Count -eq 0) {
    throw 'No GitHub token found in environment or git credential manager.'
  }

  $token = ($passwordLine[0] -replace '^password=', '').Trim()
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'GitHub token resolved to blank value.'
  }
  return $token
}

function Invoke-GitHubApi {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Method,
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [string]$Token,
    [string]$Body,
    [string]$ContentType = 'application/json',
    [string]$UploadFile
  )

  $tempBody = Join-Path ([System.IO.Path]::GetTempPath()) ("github_api_" + [System.Guid]::NewGuid().ToString('N') + '.json')
  $tempRequestBody = $null
  $args = @(
    '-sS',
    '-X', $Method,
    '-H', "Authorization: Bearer $Token",
    '-H', 'Accept: application/vnd.github+json',
    '-H', 'X-GitHub-Api-Version: 2022-11-28',
    '-H', 'User-Agent: Tutor1on1-Release-Automation',
    '-o', $tempBody,
    '-w', '%{http_code}'
  )

  if (-not [string]::IsNullOrWhiteSpace($UploadFile)) {
    $args += @(
      '-H', "Content-Type: $ContentType",
      '--data-binary', "@$UploadFile"
    )
  } elseif ($PSBoundParameters.ContainsKey('Body')) {
    $tempRequestBody = Join-Path ([System.IO.Path]::GetTempPath()) ("github_request_" + [System.Guid]::NewGuid().ToString('N') + '.json')
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tempRequestBody, $Body, $utf8NoBom)
    $args += @(
      '-H', "Content-Type: $ContentType",
      '--data-binary', "@$tempRequestBody"
    )
  }

  $args += $Url
  try {
    $statusCode = & curl.exe @args
    if ($LASTEXITCODE -ne 0) {
      throw "curl.exe failed with exit code $LASTEXITCODE for $Method $Url"
    }

    $responseText = ''
    if (Test-Path -LiteralPath $tempBody) {
      $responseText = [System.IO.File]::ReadAllText($tempBody)
    }

    return [pscustomobject]@{
      StatusCode = [int]$statusCode
      BodyText   = $responseText
    }
  } finally {
    if (Test-Path -LiteralPath $tempBody) {
      Remove-Item -LiteralPath $tempBody -Force
    }
    if ($null -ne $tempRequestBody -and (Test-Path -LiteralPath $tempRequestBody)) {
      Remove-Item -LiteralPath $tempRequestBody -Force
    }
  }
}

function Get-Release {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoSlug,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag,
    [Parameter(Mandatory = $true)]
    [string]$Token
  )

  $response = Invoke-GitHubApi `
    -Method 'GET' `
    -Url "https://api.github.com/repos/$RepoSlug/releases/tags/$ReleaseTag" `
    -Token $Token
  if ($response.StatusCode -eq 404) {
    return $null
  }
  if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
    throw "GitHub release lookup failed with status $($response.StatusCode): $($response.BodyText)"
  }
  return $response.BodyText | ConvertFrom-Json
}

function Ensure-Release {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoSlug,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseName,
    [Parameter(Mandatory = $true)]
    [string]$Token
  )

  $existing = Get-Release -RepoSlug $RepoSlug -ReleaseTag $ReleaseTag -Token $Token
  if ($null -ne $existing) {
    return $existing
  }

  $body = @{
    tag_name = $ReleaseTag
    name = $ReleaseName
    draft = $false
    prerelease = $false
    generate_release_notes = $false
  } | ConvertTo-Json -Compress

  $response = Invoke-GitHubApi `
    -Method 'POST' `
    -Url "https://api.github.com/repos/$RepoSlug/releases" `
    -Token $Token `
    -Body $body
  if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
    throw "GitHub release create failed with status $($response.StatusCode): $($response.BodyText)"
  }
  return $response.BodyText | ConvertFrom-Json
}

$repoRoot = (Resolve-Path $ProjectRoot).Path
$versionUtilsScript = Join-Path $repoRoot 'scripts\public_release_version_utils.ps1'
if (-not (Test-Path -LiteralPath $versionUtilsScript)) {
  throw "Public release version utils not found: $versionUtilsScript"
}
. $versionUtilsScript
if ([string]::IsNullOrWhiteSpace($ReleaseTag) -or [string]::IsNullOrWhiteSpace($ReleaseName)) {
  $versionInfo = Get-PublicReleaseVersionInfo -RepoRoot $repoRoot
  if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $ReleaseTag = $versionInfo.ReleaseTag
  }
  if ([string]::IsNullOrWhiteSpace($ReleaseName)) {
    $ReleaseName = $versionInfo.ReleaseName
  }
}
$packageScript = Join-Path $repoRoot 'public_release\package_github_release.ps1'
$distRoot = Join-Path $repoRoot "public_release\dist\$ReleaseTag"
$assetNames = @('Tutor1on1.apk', 'Tutor1on1.zip', 'SHA256SUMS.txt')

Push-Location $repoRoot
try {
  if (-not $SkipPackage.IsPresent) {
    $packageArgs = @(
      '-ExecutionPolicy', 'Bypass',
      '-File', $packageScript,
      '-ReleaseTag', $ReleaseTag
    )
    if ($SkipPubGet.IsPresent) {
      $packageArgs += '-SkipPubGet'
    }
    if ($SkipAnalyze.IsPresent) {
      $packageArgs += '-SkipAnalyze'
    }
    if ($SkipTest.IsPresent) {
      $packageArgs += '-SkipTest'
    }
    if ($SkipAndroidBuild.IsPresent) {
      $packageArgs += '-SkipAndroidBuild'
    }
    if ($SkipWindowsBuild.IsPresent) {
      $packageArgs += '-SkipWindowsBuild'
    }

    Invoke-Checked -Label "Package GitHub release assets ($ReleaseTag)" -Action {
      powershell @packageArgs
    }
  } else {
    Write-Host '==> Skip package requested'
  }

  if (-not (Test-Path -LiteralPath $distRoot)) {
    throw "Release dist directory not found: $distRoot"
  }

  $assetPaths = @()
  foreach ($assetName in $assetNames) {
    $assetPath = Join-Path $distRoot $assetName
    if (-not (Test-Path -LiteralPath $assetPath)) {
      throw "Missing release asset: $assetPath"
    }
    $assetPaths += $assetPath
  }

  $token = Get-GitHubToken
  $release = Ensure-Release -RepoSlug $RepoSlug -ReleaseTag $ReleaseTag -ReleaseName $ReleaseName -Token $token
  Write-Host "==> GitHub release ready: id=$($release.id) tag=$($release.tag_name)"

  foreach ($asset in @($release.assets)) {
    if ($assetNames -notcontains $asset.name) {
      continue
    }
    $deleteResponse = Invoke-GitHubApi `
      -Method 'DELETE' `
      -Url "https://api.github.com/repos/$RepoSlug/releases/assets/$($asset.id)" `
      -Token $token
    if ($deleteResponse.StatusCode -ne 204) {
      throw "Failed to delete existing asset $($asset.name). Status=$($deleteResponse.StatusCode)"
    }
    Write-Host "Deleted existing asset: $($asset.name)"
  }

  foreach ($assetPath in $assetPaths) {
    $assetName = Split-Path -Leaf $assetPath
    $uploadUrl = "https://uploads.github.com/repos/$RepoSlug/releases/$($release.id)/assets?name=$assetName"
    $uploadResponse = Invoke-GitHubApi `
      -Method 'POST' `
      -Url $uploadUrl `
      -Token $token `
      -UploadFile $assetPath `
      -ContentType 'application/octet-stream'
    if ($uploadResponse.StatusCode -lt 200 -or $uploadResponse.StatusCode -ge 300) {
      throw "Failed to upload $assetName. Status=$($uploadResponse.StatusCode) Body=$($uploadResponse.BodyText)"
    }
    $uploaded = $uploadResponse.BodyText | ConvertFrom-Json
    Write-Host "Uploaded $assetName -> $($uploaded.browser_download_url)"
  }

  Write-Host '==> GitHub release publish completed'
  Write-Host "Release URL: $($release.html_url)"
} finally {
  Pop-Location
}
