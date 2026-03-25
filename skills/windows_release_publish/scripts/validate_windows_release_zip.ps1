param(
  [Parameter(Mandatory = $true)]
  [string]$ZipPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ZipPath)) {
  throw "ZIP file not found: $ZipPath"
}

$requiredEntries = @(
  'tutor1on1.exe',
  'data/flutter_assets/AssetManifest.bin',
  'data/flutter_assets/assets/prompts/learn.prompt.txt',
  'data/flutter_assets/assets/prompts/review.prompt.txt'
)

$promptEntries = @(
  'data/flutter_assets/assets/prompts/learn.prompt.txt',
  'data/flutter_assets/assets/prompts/review.prompt.txt'
)

function Normalize-EntryPath {
  param([string]$Value)
  $normalized = $Value.Replace('\', '/')
  while ($normalized.StartsWith('./')) {
    $normalized = $normalized.Substring(2)
  }
  return $normalized
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
  $entryByPath = @{}
  foreach ($entry in $zip.Entries) {
    if ($entry.FullName.StartsWith('./')) {
      throw "ZIP entry must not use tar-style './' prefix: $($entry.FullName)"
    }
    if ($entry.FullName.Contains('\')) {
      throw "ZIP entry must use forward slashes only: $($entry.FullName)"
    }
    $entryByPath[(Normalize-EntryPath -Value $entry.FullName)] = $entry
  }

  foreach ($requiredPath in $requiredEntries) {
    if (-not $entryByPath.ContainsKey($requiredPath)) {
      throw "Required ZIP entry missing: $requiredPath"
    }
  }

  $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
  foreach ($promptPath in $promptEntries) {
    $entry = $entryByPath[$promptPath]
    $stream = $null
    $memory = $null
    try {
      $stream = $entry.Open()
      $memory = [System.IO.MemoryStream]::new()
      $stream.CopyTo($memory)
      $bytes = $memory.ToArray()
      if ($bytes.Length -eq 0) {
        throw "Prompt entry is empty: $promptPath"
      }
      $text = $strictUtf8.GetString($bytes)
      if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Prompt entry decoded to blank content: $promptPath"
      }
      if ($text.Contains('%TSD-Header-###%')) {
        throw "Prompt entry contains binary header marker: $promptPath"
      }
      if (-not $text.Contains('You are a one-on-one teacher.')) {
        throw "Prompt entry missing expected tutor header text: $promptPath"
      }
    } catch {
      throw "Prompt entry validation failed for $promptPath. $_"
    } finally {
      if ($memory -ne $null) {
        $memory.Dispose()
      }
      if ($stream -ne $null) {
        $stream.Dispose()
      }
    }
  }
} finally {
  $zip.Dispose()
}

Write-Host "ZIP validation passed: $ZipPath"
