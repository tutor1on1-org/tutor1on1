param(
  [switch]$CheckOnly,
  [switch]$SkipDateUpdate
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$today = Get-Date -Format "yyyy-MM-dd"

$memoryFiles = @(
  "AGENTS.md",
  "README.md",
  "WORKFLOW.md",
  "SCRIPTS.md",
  "BUGS.md",
  "TODOS.md",
  "LOGBOOK.md",
  "WORKLOG.md",
  "PLANS.md",
  "DONEs.md",
  "BACKUP_DRILL.md"
)

function Normalize-ExperienceSection {
  param([string[]]$Lines)

  $output = New-Object System.Collections.Generic.List[string]
  $insideSection = $false
  $seen = @{}

  foreach ($line in $Lines) {
    if ($line -match "^## Experience updates\s*$") {
      $insideSection = $true
      $output.Add($line)
      continue
    }

    if ($insideSection -and $line -match "^##\s+") {
      $insideSection = $false
    }

    if ($insideSection -and $line -match "^\-\s+") {
      $key = ($line.Trim().ToLowerInvariant() -replace "\s+", " ")
      if ($seen.ContainsKey($key)) {
        continue
      }
      $seen[$key] = $true
    }

    $output.Add($line)
  }

  return ,$output.ToArray()
}

function Normalize-Content {
  param(
    [string]$FileName,
    [string]$Raw
  )

  $text = $Raw -replace "`r`n?", "`n"
  $lines = $text -split "`n", -1 | ForEach-Object { $_.TrimEnd() }

  if (-not $SkipDateUpdate) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match "^Last updated:\s+\d{4}-\d{2}-\d{2}$") {
        $lines[$i] = "Last updated: $today"
      }
    }
  }

  if ($FileName -eq "AGENTS.md") {
    $lines = Normalize-ExperienceSection -Lines $lines
  }

  $clean = New-Object System.Collections.Generic.List[string]
  $blankRun = 0
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      $blankRun++
      if ($blankRun -gt 1) {
        continue
      }
      $clean.Add("")
      continue
    }
    $blankRun = 0
    $clean.Add($line)
  }

  while ($clean.Count -gt 0 -and [string]::IsNullOrWhiteSpace($clean[$clean.Count - 1])) {
    $clean.RemoveAt($clean.Count - 1)
  }

  return (($clean -join "`n") + "`n")
}

$changed = New-Object System.Collections.Generic.List[string]

foreach ($relativePath in $memoryFiles) {
  $fullPath = Join-Path $repoRoot $relativePath
  if (-not (Test-Path $fullPath)) {
    throw "Required memory file missing: $relativePath"
  }

  $raw = [System.IO.File]::ReadAllText($fullPath)
  $normalized = Normalize-Content -FileName $relativePath -Raw $raw

  if ($raw -ne $normalized) {
    $changed.Add($relativePath)
    if (-not $CheckOnly) {
      [System.IO.File]::WriteAllText(
        $fullPath,
        $normalized,
        [System.Text.UTF8Encoding]::new($false)
      )
    }
  }
}

if ($changed.Count -eq 0) {
  Write-Output "Memory is already consolidated."
  exit 0
}

if ($CheckOnly) {
  Write-Output "Memory consolidation required for:"
  $changed | ForEach-Object { Write-Output " - $_" }
  exit 1
}

Write-Output "Consolidated memory files:"
$changed | ForEach-Object { Write-Output " - $_" }
