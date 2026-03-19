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

function Assert-Http200 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url
  )
  $headers = & curl.exe -k -I --max-time 20 $Url
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
  $body = & curl.exe -k --fail --silent --show-error $Url
  if ($LASTEXITCODE -ne 0) {
    throw "curl body fetch failed for $Url with exit code $LASTEXITCODE."
  }
  $bodyText = ($body | Out-String)
  $escapedText = [regex]::Escape($LiteralText)
  if (-not ($bodyText | Select-String -Pattern $escapedText -Quiet)) {
    throw "Body verification failed for $Url. Missing text: $LiteralText"
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

$sources = Get-ChildItem -LiteralPath $resolvedWebDir -Force | ForEach-Object {
  $_.FullName
}
if ($sources.Count -eq 0) {
  throw "No website files found under: $resolvedWebDir"
}

Push-Location $repoRoot
try {
  Invoke-Checked -Label 'Sync local web directory to remote website root' -Action {
    scp `
      -r `
      -i $KeyPath `
      -o 'IdentitiesOnly=yes' `
      -o 'BatchMode=yes' `
      -o 'StrictHostKeyChecking=accept-new' `
      @sources `
      "${RemoteUser}@${RemoteHost}:$RemoteWebsiteDir/"
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

  $paths = @(
    '/',
    '/help/',
    '/zh/',
    '/zh/help/'
  )
  foreach ($path in $paths) {
    $url = "$($SiteBaseUrl.TrimEnd('/'))$path"
    Write-Host "==> Verify page: $url"
    Assert-Http200 -Url $url
    Assert-BodyContains -Url $url -LiteralText 'family_teacher.apk'
  }

  Write-Host '==> Website publish completed'
} finally {
  Pop-Location
}
