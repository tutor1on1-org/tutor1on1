param(
  [string]$RemoteHost = $env:FT_REMOTE_HOST,
  [string]$RemoteUser = $env:FT_REMOTE_USER,
  [string]$KeyPath = $env:FT_REMOTE_KEY_PATH,
  [string]$ServiceName = 'family-teacher-api.service',
  [string]$EnvFile = '/etc/family_teacher_remote/env'
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

function Escape-SingleQuotes {
  param([Parameter(Mandatory = $true)][string]$Value)
  $replacement = "'" + '"' + "'" + '"' + "'"
  return $Value.Replace("'", $replacement)
}

function Convert-NginxSizeToBytes {
  param([Parameter(Mandatory = $true)][string]$Value)
  $normalized = $Value.Trim().ToLowerInvariant()
  if ($normalized -eq '0') {
    return [Int64]::MaxValue
  }
  $match = [regex]::Match($normalized, '^(?<num>\d+)(?<unit>[kmg])?$')
  if (-not $match.Success) {
    throw "Unsupported nginx size value: $Value"
  }
  $num = [int64]$match.Groups['num'].Value
  $unit = $match.Groups['unit'].Value
  switch ($unit) {
    'k' { return $num * 1024L }
    'm' { return $num * 1024L * 1024L }
    'g' { return $num * 1024L * 1024L * 1024L }
    default { return $num }
  }
}

function Format-Bytes {
  param([Parameter(Mandatory = $true)][int64]$Bytes)
  if ($Bytes -eq [Int64]::MaxValue) {
    return 'unlimited'
  }
  return "$Bytes bytes"
}

$escapedService = Escape-SingleQuotes -Value $ServiceName
$escapedEnvFile = Escape-SingleQuotes -Value $EnvFile

$remoteScriptTemplate = @'
set -euo pipefail

SERVICE_NAME='__SERVICE_NAME__'
ENV_FILE='__ENV_FILE__'

resolve_bin() {
  local preferred="$1"
  local fallback="$2"
  if [[ -x "$preferred" ]]; then
    printf '%s' "$preferred"
    return 0
  fi
  command -v "$fallback"
}

SUDO_BIN="$(resolve_bin "/usr/bin/sudo" "sudo")"
SYSTEMCTL_BIN="$(resolve_bin "/usr/bin/systemctl" "systemctl")"
PS_BIN="$(resolve_bin "/usr/bin/ps" "ps")"
AWK_BIN="$(resolve_bin "/usr/bin/awk" "awk")"
NGINX_BIN="$(resolve_bin "/usr/sbin/nginx" "nginx")"
BASH_BIN="$(resolve_bin "/usr/bin/bash" "bash")"
RM_BIN="$(resolve_bin "/bin/rm" "rm")"

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

extract_env_value() {
  local key="$1"
  local raw
  raw="$("$SUDO_BIN" "$AWK_BIN" -v key="$key" '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/\r$/, "", line)
      pattern = "^[[:space:]]*" key "[[:space:]]*="
      if (line ~ pattern) {
        sub(pattern, "", line)
        value = line
      }
    }
    END {
      if (value != "") {
        print value
      }
    }
  ' "$ENV_FILE")"
  trim_value "$raw"
}

if ! "$SUDO_BIN" test -r "$ENV_FILE"; then
  echo "ERROR=env_file_not_readable"
  exit 10
fi

api_user="$("$SYSTEMCTL_BIN" show "$SERVICE_NAME" -p User --value 2>/dev/null || true)"
api_user="$(trim_value "$api_user")"
if [[ -z "$api_user" ]]; then
  echo "ERROR=service_user_missing"
  exit 11
fi

storage_root="$(extract_env_value "STORAGE_ROOT")"
bundle_max_bytes="$(extract_env_value "BUNDLE_MAX_BYTES")"
if [[ -z "$storage_root" ]]; then
  echo "ERROR=storage_root_missing_in_env"
  exit 12
fi
if [[ -z "$bundle_max_bytes" ]]; then
  echo "ERROR=bundle_max_bytes_missing_in_env"
  exit 13
fi
if ! [[ "$bundle_max_bytes" =~ ^[0-9]+$ ]]; then
  echo "ERROR=bundle_max_bytes_invalid"
  exit 14
fi
if ! "$SUDO_BIN" test -d "$storage_root"; then
  echo "ERROR=storage_root_not_found"
  exit 15
fi

perm_api_access_ok=0
perm_api_write_probe_ok=0
if "$SUDO_BIN" -u "$api_user" test -x "$storage_root" && "$SUDO_BIN" -u "$api_user" test -w "$storage_root"; then
  perm_api_access_ok=1
fi

probe_file="$storage_root/.ft_preflight_probe_$$"
if [[ "$perm_api_access_ok" -eq 1 ]]; then
  if "$SUDO_BIN" -u "$api_user" env FT_PROBE_FILE="$probe_file" "$BASH_BIN" -lc 'umask 027; printf "%s" "probe" > "$FT_PROBE_FILE"'; then
    perm_api_write_probe_ok=1
  fi
fi

nginx_user="$("$PS_BIN" -eo user=,comm=,args= | "$AWK_BIN" '$2 == "nginx" && $0 ~ /worker process/ { print $1; exit }')"
if [[ -z "$nginx_user" ]]; then
  nginx_user="$("$SUDO_BIN" "$NGINX_BIN" -T 2>/dev/null | "$AWK_BIN" '
    {
      line = $0
      sub(/#.*/, "", line)
      if (line ~ /^[[:space:]]*user[[:space:]]+[^;]+;/) {
        sub(/^[[:space:]]*user[[:space:]]+/, "", line)
        sub(/;.*/, "", line)
        gsub(/[[:space:]]+/, "", line)
        if (line != "") {
          print line
          exit
        }
      }
    }
  ')"
fi
if [[ -z "$nginx_user" ]]; then
  nginx_user="nginx"
fi

perm_nginx_traverse_ok=0
perm_nginx_read_probe_ok=0
if "$SUDO_BIN" -u "$nginx_user" test -x "$storage_root"; then
  perm_nginx_traverse_ok=1
fi
if [[ -f "$probe_file" ]] && "$SUDO_BIN" -u "$nginx_user" test -r "$probe_file"; then
  perm_nginx_read_probe_ok=1
fi

"$SUDO_BIN" -u "$api_user" env FT_PROBE_FILE="$probe_file" FT_RM_BIN="$RM_BIN" "$BASH_BIN" -lc '"$FT_RM_BIN" -f "$FT_PROBE_FILE"' || "$SUDO_BIN" "$RM_BIN" -f "$probe_file"

nginx_limits="$("$SUDO_BIN" "$NGINX_BIN" -T 2>/dev/null | "$AWK_BIN" '
  {
    line = $0
    sub(/#.*/, "", line)
    while (match(line, /client_max_body_size[[:space:]]+[^;]+;/)) {
      value = substr(line, RSTART, RLENGTH)
      sub(/client_max_body_size[[:space:]]+/, "", value)
      sub(/;.*/, "", value)
      gsub(/[[:space:]]+/, "", value)
      if (value != "") {
        limits[value] = 1
      }
      line = substr(line, RSTART + RLENGTH)
    }
  }
  END {
    first = 1
    for (v in limits) {
      if (!first) {
        printf(",")
      }
      printf("%s", v)
      first = 0
    }
  }
')" 

echo "SERVICE_NAME=$SERVICE_NAME"
echo "API_USER=$api_user"
echo "STORAGE_ROOT=$storage_root"
echo "BUNDLE_MAX_BYTES=$bundle_max_bytes"
echo "NGINX_USER=$nginx_user"
echo "NGINX_CLIENT_MAX_BODY_SIZE=$nginx_limits"
echo "PERM_API_ACCESS_OK=$perm_api_access_ok"
echo "PERM_API_WRITE_PROBE_OK=$perm_api_write_probe_ok"
echo "PERM_NGINX_TRAVERSE_OK=$perm_nginx_traverse_ok"
echo "PERM_NGINX_READ_PROBE_OK=$perm_nginx_read_probe_ok"
'@

$remoteScript = $remoteScriptTemplate.
  Replace('__SERVICE_NAME__', $escapedService).
  Replace('__ENV_FILE__', $escapedEnvFile)

Write-Host "Running remote preflight on $remote"
$rawOutput = $remoteScript | & ssh @sshArgs $remote "/usr/bin/bash -s --"
if ($LASTEXITCODE -ne 0) {
  throw "Remote preflight command failed with exit code $LASTEXITCODE."
}

$kv = @{}
foreach ($line in ($rawOutput -split "`r?`n")) {
  if ([string]::IsNullOrWhiteSpace($line)) {
    continue
  }
  if ($line -match '^([^=]+)=(.*)$') {
    $key = $matches[1].Trim()
    $value = $matches[2].Trim()
    $kv[$key] = $value
  }
}

if ($kv.ContainsKey('ERROR')) {
  throw "Remote preflight reported error: $($kv['ERROR'])"
}

$requiredKeys = @(
  'SERVICE_NAME',
  'API_USER',
  'STORAGE_ROOT',
  'BUNDLE_MAX_BYTES',
  'NGINX_USER',
  'NGINX_CLIENT_MAX_BODY_SIZE',
  'PERM_API_ACCESS_OK',
  'PERM_API_WRITE_PROBE_OK',
  'PERM_NGINX_TRAVERSE_OK',
  'PERM_NGINX_READ_PROBE_OK'
)
foreach ($key in $requiredKeys) {
  if (-not $kv.ContainsKey($key)) {
    throw "Missing expected output key from remote preflight: $key"
  }
}

$bundleMaxBytes = 0L
if (-not [int64]::TryParse($kv['BUNDLE_MAX_BYTES'], [ref]$bundleMaxBytes)) {
  throw "Invalid BUNDLE_MAX_BYTES from remote preflight: $($kv['BUNDLE_MAX_BYTES'])"
}

$nginxRawValues = @()
if (-not [string]::IsNullOrWhiteSpace($kv['NGINX_CLIENT_MAX_BODY_SIZE'])) {
  $nginxRawValues = $kv['NGINX_CLIENT_MAX_BODY_SIZE'].Split(',') |
    ForEach-Object { $_.Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

$failures = New-Object System.Collections.Generic.List[string]

if ($kv['PERM_API_ACCESS_OK'] -ne '1') {
  $failures.Add("API user '$($kv['API_USER'])' cannot write/traverse STORAGE_ROOT '$($kv['STORAGE_ROOT'])'.")
}
if ($kv['PERM_API_WRITE_PROBE_OK'] -ne '1') {
  $failures.Add("API user '$($kv['API_USER'])' could not create probe file in '$($kv['STORAGE_ROOT'])'.")
}
if ($kv['PERM_NGINX_TRAVERSE_OK'] -ne '1') {
  $failures.Add("Nginx user '$($kv['NGINX_USER'])' cannot traverse STORAGE_ROOT '$($kv['STORAGE_ROOT'])'.")
}
if ($kv['PERM_NGINX_READ_PROBE_OK'] -ne '1') {
  $failures.Add("Nginx user '$($kv['NGINX_USER'])' could not read API-created probe file in '$($kv['STORAGE_ROOT'])'.")
}

if ($nginxRawValues.Count -eq 0) {
  $failures.Add('No nginx client_max_body_size directive found in `nginx -T` output.')
} else {
  $nginxLimitBytes = New-Object System.Collections.Generic.List[int64]
  foreach ($raw in $nginxRawValues) {
    try {
      $nginxLimitBytes.Add((Convert-NginxSizeToBytes -Value $raw))
    } catch {
      $failures.Add("Unable to parse nginx client_max_body_size value '$raw'.")
    }
  }
  if ($nginxLimitBytes.Count -gt 0) {
    $uniqueLimitBytes = @($nginxLimitBytes | Sort-Object -Unique)
    if ($uniqueLimitBytes.Count -ne 1) {
      $uniqueDisplay = ($nginxRawValues | Sort-Object -Unique) -join ', '
      $failures.Add("Multiple nginx client_max_body_size values found: $uniqueDisplay. Align to one value equal to BUNDLE_MAX_BYTES.")
    } else {
      $nginxLimit = [int64]$uniqueLimitBytes[0]
      if ($nginxLimit -eq [Int64]::MaxValue) {
        $failures.Add("nginx client_max_body_size is unlimited (0); expected exact match with BUNDLE_MAX_BYTES=$bundleMaxBytes.")
      } elseif ($nginxLimit -ne $bundleMaxBytes) {
        $failures.Add("Upload size mismatch: BUNDLE_MAX_BYTES=$bundleMaxBytes but nginx client_max_body_size=$nginxLimit.")
      }
    }
  }
}

Write-Host "Service           : $($kv['SERVICE_NAME'])"
Write-Host "API user          : $($kv['API_USER'])"
Write-Host "Nginx user        : $($kv['NGINX_USER'])"
Write-Host "Storage root      : $($kv['STORAGE_ROOT'])"
Write-Host "BUNDLE_MAX_BYTES  : $(Format-Bytes -Bytes $bundleMaxBytes)"
if ($nginxRawValues.Count -gt 0) {
  Write-Host "Nginx size values : $($nginxRawValues -join ', ')"
}

if ($failures.Count -gt 0) {
  Write-Host ''
  Write-Host 'Preflight FAILED:'
  foreach ($failure in $failures) {
    Write-Host " - $failure"
  }
  exit 1
}

Write-Host ''
Write-Host 'Preflight PASSED: storage permissions and upload-size config are aligned.'
