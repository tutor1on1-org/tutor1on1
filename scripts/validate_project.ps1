param(
  [switch]$SkipFlutter,
  [switch]$SkipGo,
  [switch]$SkipAnalyze,
  [switch]$SkipFlutterTest,
  [switch]$RunPostHook,
  [switch]$NoPostHook
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Invoke-Step {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  Write-Output "==> $Name"
  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
}

function Resolve-GoExe {
  $goCommand = Get-Command go -ErrorAction SilentlyContinue
  if ($goCommand) {
    return $goCommand.Source
  }
  $fallback = "C:\Program Files\Go\bin\go.exe"
  if (Test-Path $fallback) {
    return $fallback
  }
  throw "go executable not found (tried PATH and $fallback)"
}

Push-Location $repoRoot
try {
  if (-not $SkipFlutter) {
    Invoke-Step -Name "flutter pub get" -Action { & flutter pub get }
    if (-not $SkipAnalyze) {
      Invoke-Step -Name "flutter analyze --no-pub" -Action {
        & flutter analyze --no-pub
      }
    }
    if (-not $SkipFlutterTest) {
      Invoke-Step -Name "flutter test --no-pub" -Action {
        & flutter test --no-pub
      }
    }
  }

  if (-not $SkipGo) {
    $goExe = Resolve-GoExe
    Invoke-Step -Name "go test ./... (remote/)" -Action {
      Push-Location (Join-Path $repoRoot "remote")
      try {
        & $goExe test ./...
      } finally {
        Pop-Location
      }
    }
  }
} finally {
  Pop-Location
}

Write-Output "Validation passed."

if ($RunPostHook -and -not $NoPostHook) {
  $hookScript = Join-Path $PSScriptRoot "post_validate_hook.ps1"
  & $hookScript
}
