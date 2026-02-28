param(
  [string]$SnapshotPath = "scripts/memory_line_snapshot.json",
  [string]$SessionStatePath = "scripts/memory_hook_agent/memory_hook_state.json",
  [string]$PromptPath = "scripts/memory_hook_agent/AGENTS.template.md",
  [int]$LineDeltaThreshold = 10,
  [string]$CodexCommand = "codex",
  [string[]]$ForceTargets = @(),
  [switch]$SimulateOnly,
  [switch]$SkipGitOps,
  [string]$MemoryCommitMessage = "docs: memory hook update"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$subAgentDir = Join-Path $repoRoot "scripts\memory_hook_agent"
$subAgentAgentsPath = Join-Path $subAgentDir "AGENTS.md"
$schemaFile = Join-Path $subAgentDir "memory_hook_output_schema.json"
$promptFile = Join-Path $repoRoot $PromptPath
$snapshotFile = Join-Path $repoRoot $SnapshotPath
$sessionStateFile = Join-Path $repoRoot $SessionStatePath
$convertFromJsonCommand = Get-Command ConvertFrom-Json -ErrorAction Stop
$supportsConvertFromJsonDepth = $convertFromJsonCommand.Parameters.ContainsKey("Depth")

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
$memoryTrackedFiles = @(
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
  "scripts/memory_line_snapshot.json",
  "scripts/memory_hook_agent/AGENTS.md",
  "scripts/memory_hook_agent/memory_hook_state.json"
)

function Ensure-FileExists {
  param([string]$Path, [string]$Label)
  if (-not (Test-Path $Path)) {
    throw "$Label not found: $Path"
  }
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Ensure-ParentDirectory {
  param([string]$Path)
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    Ensure-Directory -Path $parent
  }
}

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    return $null
  }
  $raw = [System.IO.File]::ReadAllText($Path)
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $null
  }
  return ConvertFrom-JsonCompat -Json $raw -Depth 20
}

function ConvertFrom-JsonCompat {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Json,
    [int]$Depth = 20
  )
  if ($supportsConvertFromJsonDepth) {
    return $Json | ConvertFrom-Json -Depth $Depth
  }
  return $Json | ConvertFrom-Json
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Object
  )
  Ensure-ParentDirectory -Path $Path
  $json = $Object | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText(
    $Path,
    $json + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
}

function Get-LineCount {
  param([string]$RelativePath)
  $full = Join-Path $repoRoot $RelativePath
  Ensure-FileExists -Path $full -Label "Memory file"
  return ([System.IO.File]::ReadLines($full) | Measure-Object).Count
}

function Get-MemorySnapshot {
  $lines = [ordered]@{}
  foreach ($file in $memoryFiles) {
    $lines[$file] = Get-LineCount -RelativePath $file
  }
  return [ordered]@{
    line_counts = $lines
  }
}

function Normalize-PathKey {
  param([string]$Value)
  return $Value.Trim().Replace("/", "\")
}

function Write-Info {
  param([string]$Message)
  if (-not $SimulateOnly) {
    Write-Output $Message
  }
}

function Resolve-Targets {
  param([string[]]$RequestedTargets)
  $resolved = New-Object System.Collections.Generic.List[string]
  $seen = @{}
  foreach ($requested in $RequestedTargets) {
    $requestedKey = (Normalize-PathKey -Value $requested).ToLowerInvariant()
    $match = $null
    foreach ($candidate in $memoryFiles) {
      $candidateKey = (Normalize-PathKey -Value $candidate).ToLowerInvariant()
      if ($candidateKey -eq $requestedKey) {
        $match = $candidate
        break
      }
    }
    if ($null -eq $match -and $requestedKey.EndsWith("s.md")) {
      $singularKey = $requestedKey.Substring(0, $requestedKey.Length - 4) + ".md"
      foreach ($candidate in $memoryFiles) {
        $candidateKey = (Normalize-PathKey -Value $candidate).ToLowerInvariant()
        if ($candidateKey -eq $singularKey) {
          $match = $candidate
          break
        }
      }
    }
    if ($null -eq $match) {
      throw "Unknown memory target: $requested"
    }
    if (-not $seen.ContainsKey($match)) {
      $seen[$match] = $true
      $resolved.Add($match)
    }
  }
  return $resolved
}

function Try-GetMapValue {
  param(
    [object]$Map,
    [string]$Key,
    [ref]$ValueRef
  )
  if ($null -eq $Map) {
    return $false
  }
  if ($Map -is [System.Collections.IDictionary]) {
    if ($Map.Contains($Key)) {
      $ValueRef.Value = $Map[$Key]
      return $true
    }
    return $false
  }
  $prop = $Map.PSObject.Properties[$Key]
  if ($null -ne $prop) {
    $ValueRef.Value = $prop.Value
    return $true
  }
  return $false
}

function Build-SubAgentWorkspace {
  Ensure-Directory -Path $subAgentDir
  Ensure-FileExists -Path $promptFile -Label "Hook prompt"
  $templatePrompt = [System.IO.File]::ReadAllText($promptFile).TrimEnd()
  $rootAgentsPath = Join-Path $repoRoot "AGENTS.md"
  Ensure-FileExists -Path $rootAgentsPath -Label "Root AGENTS.md"
  $rootAgentsContent = [System.IO.File]::ReadAllText($rootAgentsPath).TrimEnd()
  $fullPrompt = @"
$templatePrompt

## Root AGENTS.md (Full Text)
$rootAgentsContent
"@
  [System.IO.File]::WriteAllText(
    $subAgentAgentsPath,
    $fullPrompt.TrimEnd() + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  $schema = @'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["updated_files", "append_suggestions", "notes"],
  "properties": {
    "updated_files": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["path", "content"],
        "properties": {
          "path": { "type": "string" },
          "content": { "type": "string" }
        }
      }
    },
    "append_suggestions": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["path", "content_to_append"],
        "properties": {
          "path": { "type": "string" },
          "content_to_append": { "type": "string" }
        }
      }
    },
    "notes": { "type": "string" }
  }
}
'@
  [System.IO.File]::WriteAllText(
    $schemaFile,
    $schema.Trim() + "`n",
    [System.Text.UTF8Encoding]::new($false)
  )
}

function Ensure-CodexCommand {
  param([string]$CommandName)
  $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Codex command not found: $CommandName"
  }
}

function Publish-MemoryChanges {
  if ($SimulateOnly -or $SkipGitOps) {
    return
  }
  $status = @(& git status --porcelain -- $memoryTrackedFiles)
  if ($status.Count -eq 0) {
    Write-Info "No memory changes to commit or push."
    return
  }

  Write-Info "Committing memory hook changes."
  & git add -- $memoryTrackedFiles
  $cachedDiff = @(& git diff --cached --name-only -- $memoryTrackedFiles)
  if ($cachedDiff.Count -eq 0) {
    Write-Info "No staged memory changes after git add."
    return
  }

  & git commit -m $MemoryCommitMessage

  Write-Info "Pushing branch from memory hook."
  $env:FT_SKIP_PRE_PUSH_VALIDATE = "1"
  try {
    & git push
  } finally {
    Remove-Item Env:FT_SKIP_PRE_PUSH_VALIDATE -ErrorAction SilentlyContinue
  }
}

function Read-SessionId {
  $state = Read-JsonFile -Path $sessionStateFile
  if ($null -eq $state) {
    return $null
  }
  $id = ($state.session_id | ForEach-Object { $_.ToString() }).Trim()
  if ([string]::IsNullOrWhiteSpace($id)) {
    return $null
  }
  return $id
}

function Write-SessionId {
  param([string]$SessionId)
  $normalized = $SessionId.Trim()
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return
  }
  $existingId = Read-SessionId
  if ($existingId -eq $normalized) {
    return
  }
  Write-JsonFile -Path $sessionStateFile -Object ([PSCustomObject]@{
      session_id = $normalized
    })
}

function Get-CodexFinalMessage {
  param(
    [string]$JsonlOutput,
    [ref]$ThreadIdRef
  )
  $lines = $JsonlOutput -split "`r?`n"
  $finalText = $null
  foreach ($line in $lines) {
    $trim = $line.Trim()
    if ($trim.Length -eq 0) {
      continue
    }
    if (-not ($trim.StartsWith("{") -and $trim.EndsWith("}"))) {
      continue
    }
    try {
      $obj = ConvertFrom-JsonCompat -Json $trim -Depth 20
    } catch {
      continue
    }
    if ($obj.type -eq "thread.started" -and $obj.thread_id) {
      $ThreadIdRef.Value = $obj.thread_id.ToString()
    }
    if ($obj.type -eq "item.completed" -and $obj.item) {
      if ($obj.item.type -eq "agent_message" -and $obj.item.text) {
        $finalText = $obj.item.text.ToString()
      }
    }
    if ($obj.type -eq "response_item" -and $obj.payload) {
      if ($obj.payload.type -eq "message" -and
          $obj.payload.role -eq "assistant" -and
          $obj.payload.content) {
        $chunks = @()
        foreach ($contentItem in @($obj.payload.content)) {
          if ($contentItem.type -eq "output_text" -and $contentItem.text) {
            $chunks += $contentItem.text.ToString()
          }
        }
        if ($chunks.Count -gt 0) {
          $finalText = ($chunks -join "").Trim()
        }
      }
    }
  }
  if ([string]::IsNullOrWhiteSpace($finalText)) {
    throw "Codex returned no final assistant message."
  }
  return $finalText
}

function Invoke-CodexMemoryAgent {
  param(
    [string]$PromptPayloadJson
  )
  Ensure-CodexCommand -CommandName $CodexCommand
  $savedThreadId = Read-SessionId
  $threadRef = [ref]$null

  $newArgs = @(
    "exec",
    "--json",
    "--output-schema",
    $schemaFile
  )
  $resumeArgs = @(
    "exec",
    "--json",
    "resume",
    $savedThreadId
  )

  Push-Location $subAgentDir
  try {
    $output = $null
    $usedResume = $false
    if (-not [string]::IsNullOrWhiteSpace($savedThreadId)) {
      try {
        $usedResume = $true
        $output = $PromptPayloadJson | & $CodexCommand @resumeArgs
        $message = Get-CodexFinalMessage -JsonlOutput ($output | Out-String) -ThreadIdRef $threadRef
      } catch {
        $usedResume = $false
        $threadRef = [ref]$null
        $output = $PromptPayloadJson | & $CodexCommand @newArgs
        $message = Get-CodexFinalMessage -JsonlOutput ($output | Out-String) -ThreadIdRef $threadRef
      }
    } else {
      $output = $PromptPayloadJson | & $CodexCommand @newArgs
      $message = Get-CodexFinalMessage -JsonlOutput ($output | Out-String) -ThreadIdRef $threadRef
    }

    if (-not $SimulateOnly) {
      if (-not [string]::IsNullOrWhiteSpace($threadRef.Value)) {
        Write-SessionId -SessionId $threadRef.Value
      } elseif ($usedResume -and -not [string]::IsNullOrWhiteSpace($savedThreadId)) {
        Write-SessionId -SessionId $savedThreadId
      }
    }
    return $message
  } finally {
    Pop-Location
  }
}

function Build-Payload {
  param(
    [string[]]$Targets
  )
  $targetMap = @{}
  $otherNames = New-Object System.Collections.Generic.List[string]
  foreach ($path in $memoryFiles) {
    $full = Join-Path $repoRoot $path
    $content = [System.IO.File]::ReadAllText($full)
    if ($Targets -contains $path) {
      $targetMap[$path] = $content
    } elseif ($path -ne "AGENTS.md") {
      $otherNames.Add($path)
    }
  }
  $agentsContent = [System.IO.File]::ReadAllText((Join-Path $repoRoot "AGENTS.md"))
  $payload = [PSCustomObject]@{
    targets = $Targets
    agents_md = $agentsContent
    target_files = $targetMap
    other_memory_files = $otherNames.ToArray()
  }
  return ($payload | ConvertTo-Json -Depth 20)
}

function Apply-UpdatedFiles {
  param(
    [object[]]$UpdatedFiles,
    [string[]]$Targets
  )
  $validTargets = @{}
  foreach ($t in $Targets) {
    $validTargets[(Normalize-PathKey -Value $t)] = $true
  }
  $seen = @{}
  foreach ($entry in $UpdatedFiles) {
    $path = Normalize-PathKey -Value $entry.path
    if (-not $validTargets.ContainsKey($path)) {
      throw "updated_files contains non-target path: $path"
    }
    if ($seen.ContainsKey($path)) {
      throw "updated_files contains duplicate path: $path"
    }
    $seen[$path] = $true
    $full = Join-Path $repoRoot $path
    [System.IO.File]::WriteAllText(
      $full,
      ($entry.content.ToString().TrimEnd() + "`n"),
      [System.Text.UTF8Encoding]::new($false)
    )
  }
}

function Apply-AppendSuggestions {
  param(
    [object[]]$Suggestions,
    [string[]]$Targets
  )
  $targetKeys = @{}
  foreach ($t in $Targets) {
    $targetKeys[(Normalize-PathKey -Value $t)] = $true
  }
  $validMemory = @{}
  foreach ($m in $memoryFiles) {
    $validMemory[(Normalize-PathKey -Value $m)] = $true
  }
  $seen = @{}

  foreach ($entry in $Suggestions) {
    $path = Normalize-PathKey -Value $entry.path
    if (-not $validMemory.ContainsKey($path)) {
      throw "append_suggestions contains invalid path: $path"
    }
    if ($targetKeys.ContainsKey($path)) {
      throw "append_suggestions cannot target updated target file: $path"
    }
    if ($seen.ContainsKey($path)) {
      throw "append_suggestions contains duplicate path: $path"
    }
    $seen[$path] = $true
    $appendText = $entry.content_to_append.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($appendText)) {
      continue
    }
    $full = Join-Path $repoRoot $path
    $existing = [System.IO.File]::ReadAllText($full)
    $newContent = $existing.TrimEnd() + "`n`n" + $appendText + "`n"
    [System.IO.File]::WriteAllText(
      $full,
      $newContent,
      [System.Text.UTF8Encoding]::new($false)
    )
  }
}

Push-Location $repoRoot
try {
  Build-SubAgentWorkspace

  $targets = New-Object System.Collections.Generic.List[string]
  if ($ForceTargets.Count -gt 0) {
    $resolved = Resolve-Targets -RequestedTargets $ForceTargets
    foreach ($item in $resolved) {
      $targets.Add($item)
    }
  } else {
    $currentSnapshot = Get-MemorySnapshot
    $previous = Read-JsonFile -Path $snapshotFile
    if ($null -eq $previous -or $null -eq $previous.line_counts) {
      Write-Info "Memory snapshot missing. Initializing and skipping LLM update."
      Write-JsonFile -Path $snapshotFile -Object $currentSnapshot
      exit 0
    }

    $prevCounts = $previous.line_counts
    foreach ($path in $memoryFiles) {
      $prevValue = $null
      $prevRef = [ref]$null
      if (Try-GetMapValue -Map $prevCounts -Key $path -ValueRef $prevRef) {
        $prevValue = [int]$prevRef.Value
      } else {
        $prevValue = [int](Get-LineCount -RelativePath $path)
      }
      $nowValue = [int]$currentSnapshot.line_counts.$path
      $delta = [Math]::Abs($nowValue - $prevValue)
      if ($delta -gt $LineDeltaThreshold) {
        $targets.Add($path)
      }
    }

    if ($targets.Count -eq 0) {
      Write-Info "No markdown files exceeded line delta threshold."
      Write-JsonFile -Path $snapshotFile -Object $currentSnapshot
      exit 0
    }
  }

  $targetArray = $targets.ToArray()
  Write-Info ("Memory update targets: " + ($targetArray -join ", "))
  $payload = Build-Payload -Targets $targetArray
  $rawResponse = Invoke-CodexMemoryAgent -PromptPayloadJson $payload
  $responseObj = ConvertFrom-JsonCompat -Json $rawResponse -Depth 40

  if ($SimulateOnly) {
    $responseObj | ConvertTo-Json -Depth 40
    exit 0
  }

  $updatedFiles = @()
  if ($responseObj.updated_files) {
    $updatedFiles = @($responseObj.updated_files)
  }
  $appendSuggestions = @()
  if ($responseObj.append_suggestions) {
    $appendSuggestions = @($responseObj.append_suggestions)
  }

  Apply-UpdatedFiles -UpdatedFiles $updatedFiles -Targets $targetArray
  Apply-AppendSuggestions -Suggestions $appendSuggestions -Targets $targetArray

  $newSnapshot = Get-MemorySnapshot
  Write-JsonFile -Path $snapshotFile -Object $newSnapshot
  Write-Info "Memory hook update applied."
  Publish-MemoryChanges
} finally {
  Pop-Location
}
