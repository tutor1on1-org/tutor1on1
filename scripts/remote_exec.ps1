param(
  [string]$RemoteHost = $env:FT_REMOTE_HOST,
  [string]$RemoteUser = $env:FT_REMOTE_USER,
  [string]$KeyPath = $env:FT_REMOTE_KEY_PATH,
  [switch]$Tty,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandParts
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RemoteHost)) {
  $RemoteHost = '43.99.59.107'
}
if ([string]::IsNullOrWhiteSpace($RemoteUser)) {
  $RemoteUser = 'ecs-user'
}
if ([string]::IsNullOrWhiteSpace($KeyPath)) {
  $KeyPath = 'C:\Users\kl\.ssh\id_rsa'
}
if (-not (Test-Path -LiteralPath $KeyPath)) {
  throw "SSH key file not found: $KeyPath"
}

$remote = "$RemoteUser@$RemoteHost"
$sshArgs = @(
  '-i', $KeyPath,
  '-o', 'IdentitiesOnly=yes',
  '-o', 'BatchMode=yes',
  '-o', 'StrictHostKeyChecking=accept-new'
)
if ($Tty.IsPresent) {
  $sshArgs += '-t'
}

if ($CommandParts.Count -eq 0) {
  & ssh @sshArgs $remote
  exit $LASTEXITCODE
}

$remoteCommand = [string]::Join(' ', $CommandParts)
& ssh @sshArgs $remote $remoteCommand
exit $LASTEXITCODE
