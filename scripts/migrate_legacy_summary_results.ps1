param(
  [switch]$DryRun,
  [switch]$SkipLocal,
  [switch]$SkipServer,
  [string]$LocalDb = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$py = Join-Path $scriptDir 'migrate_legacy_summary_results.py'
$args = @($py)
if ($DryRun) { $args += '--dry-run' }
if ($SkipLocal) { $args += '--skip-local' }
if ($SkipServer) { $args += '--skip-server' }
if ($LocalDb.Trim() -ne '') { $args += @('--local-db', $LocalDb) }

python @args
