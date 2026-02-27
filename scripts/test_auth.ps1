param(
  [string]$BaseUrl = $env:FT_REMOTE_BASE_URL
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = 'https://43.99.59.107'
}

$BaseUrl = $BaseUrl.TrimEnd('/')

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

function Invoke-Json {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')] [string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter()][hashtable]$Body,
    [Parameter()][hashtable]$Headers
  )

  $uri = "$BaseUrl$Path"
  $payload = $null
  if ($Body) {
    $payload = ($Body | ConvertTo-Json -Depth 5)
  }

  $requestParams = @{
    Method      = $Method
    Uri         = $uri
    ContentType = 'application/json'
  }

  if ($Headers) {
    $requestParams.Headers = $Headers
  }

  if ($payload) {
    $requestParams.Body = $payload
  }

  return Invoke-RestMethod @requestParams
}

$suffix = (Get-Date -Format 'yyyyMMddHHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 6))

$studentUsername = "student_$suffix"
$studentEmail = "student_$suffix@example.com"
$studentPassword = "Student#1!$suffix"
$studentPassword2 = "Student#2!$suffix"
$studentPassword3 = "Student#3!$suffix"

$teacherUsername = "teacher_$suffix"
$teacherEmail = "teacher_$suffix@example.com"
$teacherPassword = "Teacher#1!$suffix"

Write-Host "Base URL: $BaseUrl"
Write-Host "Registering student: $studentUsername"

$studentRegister = Invoke-Json -Method 'POST' -Path '/api/auth/register-student' -Body @{
  username = $studentUsername
  email    = $studentEmail
  password = $studentPassword
}

if (-not $studentRegister.access_token) {
  throw "Student registration failed: missing access_token."
}

Write-Host "Logging in student"
$studentLogin = Invoke-Json -Method 'POST' -Path '/api/auth/login' -Body @{
  username = $studentUsername
  password = $studentPassword
}

if (-not $studentLogin.access_token) {
  throw "Student login failed: missing access_token."
}

Write-Host "Changing student password (authenticated)"
$studentChange = Invoke-Json -Method 'POST' -Path '/api/auth/change-password' -Body @{
  current_password = $studentPassword
  new_password     = $studentPassword2
} -Headers @{
  Authorization = "Bearer $($studentLogin.access_token)"
}

if ($studentChange.status -ne 'ok') {
  throw "Change password failed."
}

Write-Host "Logging in student with new password"
$studentLogin2 = Invoke-Json -Method 'POST' -Path '/api/auth/login' -Body @{
  username = $studentUsername
  password = $studentPassword2
}

if (-not $studentLogin2.access_token) {
  throw "Student login after change failed."
}

Write-Host "Requesting recovery token"
$recovery = Invoke-Json -Method 'POST' -Path '/api/auth/request-recovery' -Body @{
  email = $studentEmail
}

$recoveryToken = $recovery.recovery_token
if (-not $recoveryToken) {
  $recoveryToken = $env:FT_RECOVERY_TOKEN
}
if (-not $recoveryToken) {
  throw "Recovery token missing. In production (RECOVERY_TOKEN_ECHO=false), fetch token from SMTP inbox and pass FT_RECOVERY_TOKEN."
}

Write-Host "Resetting password via recovery token"
$reset = Invoke-Json -Method 'POST' -Path '/api/auth/reset-password' -Body @{
  email          = $studentEmail
  recovery_token = $recoveryToken
  new_password   = $studentPassword3
}

if ($reset.status -ne 'ok') {
  throw "Password reset failed."
}

Write-Host "Logging in student with recovery password"
$studentLogin3 = Invoke-Json -Method 'POST' -Path '/api/auth/login' -Body @{
  username = $studentUsername
  password = $studentPassword3
}

if (-not $studentLogin3.access_token) {
  throw "Student login after recovery failed."
}

Write-Host "Registering teacher: $teacherUsername"
$teacherRegister = Invoke-Json -Method 'POST' -Path '/api/auth/register-teacher' -Body @{
  username          = $teacherUsername
  email             = $teacherEmail
  password          = $teacherPassword
  display_name      = "Teacher $suffix"
  bio               = "Test teacher $suffix"
  avatar_url        = ""
  contact           = ""
  contact_published = $false
}

if (-not $teacherRegister.access_token) {
  throw "Teacher registration failed: missing access_token."
}

Write-Host "Auth flow tests completed successfully."
