param(
  [string]$OutputRoot = ".tmp/public_client_snapshot",
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
$readmeTemplate = Join-Path $repoRoot 'PUBLIC_CLIENT_README.md'

if (-not (Test-Path $readmeTemplate)) {
  throw "Missing README template: $readmeTemplate"
}

if (Test-Path $outputPath) {
  if (-not $Force) {
    throw "Output already exists: $outputPath. Re-run with -Force to replace it."
  }
  Remove-Item -Recurse -Force $outputPath
}

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$tracked = git -C $repoRoot ls-files
if ($LASTEXITCODE -ne 0) {
  throw 'git ls-files failed'
}

$includePrefixes = @(
  'android/',
  'assets/',
  'integration_test/',
  'ios/',
  'lib/',
  'linux/',
  'macos/',
  'packages/',
  'test/',
  'third_party/',
  'windows/'
)

$includeFiles = @(
  '.gitignore',
  '.metadata',
  'LICENSE',
  'LICENSE.txt',
  'NOTICE',
  'analysis_options.yaml',
  'l10n.yaml',
  'pubspec.lock',
  'pubspec.yaml'
)

$selected = New-Object System.Collections.Generic.List[string]

foreach ($relPath in $tracked) {
  if ([string]::IsNullOrWhiteSpace($relPath)) {
    continue
  }

  $include = $includeFiles -contains $relPath
  if (-not $include) {
    foreach ($prefix in $includePrefixes) {
      if ($relPath.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        $include = $true
        break
      }
    }
  }

  if (-not $include) {
    continue
  }

  $sourcePath = Join-Path $repoRoot $relPath
  if (-not (Test-Path $sourcePath)) {
    throw "Tracked file missing on disk: $relPath"
  }

  $destinationPath = Join-Path $outputPath $relPath
  $destinationDir = Split-Path -Parent $destinationPath
  if ($destinationDir -and -not (Test-Path $destinationDir)) {
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
  }
  Copy-Item -Path $sourcePath -Destination $destinationPath -Force
  [void]$selected.Add($relPath)
}

Copy-Item -Path $readmeTemplate -Destination (Join-Path $outputPath 'README.md') -Force

$fileListPath = Join-Path $outputPath 'SNAPSHOT_FILELIST.txt'
$fileList = @(
  'README.md'
  $selected
) | Sort-Object
Set-Content -Path $fileListPath -Value $fileList

Write-Host "Exported public client snapshot to $outputPath"
Write-Host "Copied $($selected.Count + 1) files (including README.md)."
Write-Host 'Excluded tracked areas: remote/, scripts/, web/, tool/, ops docs, and release/deploy helpers.'
