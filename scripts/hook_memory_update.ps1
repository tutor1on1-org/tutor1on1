param(
  [string]$SnapshotPath = "scripts/memory_line_snapshot.json",
  [string]$SessionStatePath = ".git/memory_hook_state.json",
  [string]$PromptPath = "scripts/hook_memory_update_prompt.txt",
  [int]$LineDeltaThreshold = 10,
  [string]$CodexCommand = "codex"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$promptFile = Join-Path $repoRoot $PromptPath
$snapshotFile = Join-Path $repoRoot $SnapshotPath
$sessionStateFile = Join-Path $repoRoot $SessionStatePath

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

$subAgentDir = Join-Path $repoRoot ".git\memory_hook_agent"
$subAgentAgentsPath = Join-Path $subAgentDir "AGENTS.md"
$schemaFile = Join-Path $subAgentDir "memory_hook_output_schema.json"

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
  return $raw | ConvertFrom-Json
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
  $prompt = [System.IO.File]::ReadAllText($promptFile)
  [System.IO.File]::WriteAllText(
    $subAgentAgentsPath,
    $prompt.TrimEnd() + "`n",
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
  if ([string]::IsNullOrWhiteSpace($SessionId)) {
    return
  }
  Write-JsonFile -Path $sessionStateFile -Object ([PSCustomObject]@{
      session_id = $SessionId.Trim()
      updated_at = (Get-Date).ToUniversalTime().ToString("o")
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
      $obj = $trim | ConvertFrom-Json -Depth 20
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
    $schemaFile,
    "-C",
    $subAgentDir
  )
  $resumeArgs = @(
    "exec",
    "--json",
    "resume",
    $savedThreadId,
    "--output-schema",
    $schemaFile,
    "-C",
    $subAgentDir
  )

  $output = $null
  $usedResume = $false
  if (-not [string]::IsNullOrWhiteSpace($savedThreadId)) {
    try {
      $usedResume = $true
      $output = $PromptPayloadJson | & $CodexCommand @resumeArgs
    } catch {
      $usedResume = $false
      $output = $PromptPayloadJson | & $CodexCommand @newArgs
    }
  } else {
    $output = $PromptPayloadJson | & $CodexCommand @newArgs
  }

  $message = Get-CodexFinalMessage -JsonlOutput ($output | Out-String) -ThreadIdRef $threadRef
  if (-not [string]::IsNullOrWhiteSpace($threadRef.Value)) {
    Write-SessionId -SessionId $threadRef.Value
  } elseif ($usedResume -and -not [string]::IsNullOrWhiteSpace($savedThreadId)) {
    Write-SessionId -SessionId $savedThreadId
  }
  return $message
}

function Build-Payload {
  param(
    [string[]]$Targets
  )
  $targetMap = @{}
  $otherMap = @{}
  foreach ($path in $memoryFiles) {
    $full = Join-Path $repoRoot $path
    $content = [System.IO.File]::ReadAllText($full)
    if ($Targets -contains $path) {
      $targetMap[$path] = $content
    } elseif ($path -ne "AGENTS.md") {
      $otherMap[$path] = $content
    }
  }
  $agentsContent = [System.IO.File]::ReadAllText((Join-Path $repoRoot "AGENTS.md"))
  $payload = [PSCustomObject]@{
    targets = $Targets
    agents_md = $agentsContent
    target_files = $targetMap
    other_memory_files = $otherMap
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

  $currentSnapshot = Get-MemorySnapshot
  $previous = Read-JsonFile -Path $snapshotFile
  if ($null -eq $previous -or $null -eq $previous.line_counts) {
    Write-Output "Memory snapshot missing. Initializing and skipping LLM update."
    Write-JsonFile -Path $snapshotFile -Object $currentSnapshot
    exit 0
  }

  $prevCounts = $previous.line_counts
  $targets = New-Object System.Collections.Generic.List[string]
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
    Write-Output "No markdown files exceeded line delta threshold."
    Write-JsonFile -Path $snapshotFile -Object $currentSnapshot
    exit 0
  }

  Write-Output ("Memory update targets: " + ($targets -join ", "))
  $payload = Build-Payload -Targets $targets.ToArray()
  $rawResponse = Invoke-CodexMemoryAgent -PromptPayloadJson $payload
  $responseObj = $rawResponse | ConvertFrom-Json -Depth 40

  $updatedFiles = @()
  if ($responseObj.updated_files) {
    $updatedFiles = @($responseObj.updated_files)
  }
  $appendSuggestions = @()
  if ($responseObj.append_suggestions) {
    $appendSuggestions = @($responseObj.append_suggestions)
  }

  Apply-UpdatedFiles -UpdatedFiles $updatedFiles -Targets $targets.ToArray()
  Apply-AppendSuggestions -Suggestions $appendSuggestions -Targets $targets.ToArray()

  $newSnapshot = Get-MemorySnapshot
  Write-JsonFile -Path $snapshotFile -Object $newSnapshot
  Write-Output "Memory hook update applied."
} finally {
  Pop-Location
}
