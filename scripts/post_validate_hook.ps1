param(
  [string]$MemoryCommitMessage = "docs: memory hook update"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$memoryHookScript = Join-Path $PSScriptRoot "hook_memory_update.ps1"

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
  "BACKUP_DRILL.md",
  "scripts/memory_line_snapshot.json"
)

Push-Location $repoRoot
try {
  Write-Output "==> Running memory update hook"
  & $memoryHookScript

  $status = @(& git status --porcelain -- $memoryFiles)
  if ($status.Count -gt 0) {
    Write-Output "==> Committing memory hook changes"
    & git add -- $memoryFiles
    $cachedDiff = @(& git diff --cached --name-only -- $memoryFiles)
    if ($cachedDiff.Count -gt 0) {
      & git commit -m $MemoryCommitMessage
    }
  }

  Write-Output "==> Pushing branch"
  $env:FT_SKIP_PRE_PUSH_VALIDATE = "1"
  try {
    & git push
  } finally {
    Remove-Item Env:FT_SKIP_PRE_PUSH_VALIDATE -ErrorAction SilentlyContinue
  }
} finally {
  Pop-Location
}
