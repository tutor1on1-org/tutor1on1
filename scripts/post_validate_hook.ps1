param(
  [string]$MemoryCommitMessage = "docs: memory hook update"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$memoryHookScript = Join-Path $PSScriptRoot "hook_memory_update.ps1"

Push-Location $repoRoot
try {
  Write-Output "==> Running memory update hook (with git publish)"
  & $memoryHookScript -MemoryCommitMessage $MemoryCommitMessage
} finally {
  Pop-Location
}
