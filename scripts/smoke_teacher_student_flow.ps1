param(
  [string]$BaseUrl = $env:FT_REMOTE_BASE_URL,
  [string]$AdminUsername = $env:FT_SMOKE_ADMIN_USERNAME,
  [string]$AdminPassword = $env:FT_SMOKE_ADMIN_PASSWORD,
  [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = 'https://api.tutor1on1.org'
}
$BaseUrl = $BaseUrl.TrimEnd('/')
Add-Type -AssemblyName System.Net.Http

function Invoke-Json {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')] [string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter()][hashtable]$Body,
    [Parameter()][string]$AccessToken
  )

  $uri = "$BaseUrl$Path"
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($AccessToken)) {
    $headers['Authorization'] = "Bearer $AccessToken"
  }

  $params = @{
    Method      = $Method
    Uri         = $uri
    Headers     = $headers
    ContentType = 'application/json'
  }
  if ($Body) {
    $params['Body'] = ($Body | ConvertTo-Json -Depth 8)
  }

  try {
    return Invoke-RestMethod @params
  } catch {
    $response = $_.Exception.Response
    if ($null -eq $response) {
      throw
    }
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
    $raw = $reader.ReadToEnd()
    $reader.Dispose()
    throw "HTTP $($response.StatusCode.value__) $Method $Path failed: $raw"
  }
}

function Invoke-AuthLogin {
  param(
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$Password
  )

  return Invoke-Json -Method 'POST' -Path '/api/auth/login' -Body @{
    username = $Username
    password = $Password
  }
}

function Expand-JsonList {
  param(
    [Parameter(Mandatory = $true)]$Value
  )

  $items = @($Value)
  if ($items.Count -eq 1 -and $items[0] -is [System.Array]) {
    return @($items[0])
  }
  return $items
}

function Get-AdminAccessToken {
  param(
    [Parameter(Mandatory = $true)][ref]$CachedToken
  )

  if (-not [string]::IsNullOrWhiteSpace($CachedToken.Value)) {
    return $CachedToken.Value
  }
  if ([string]::IsNullOrWhiteSpace($AdminUsername) -or [string]::IsNullOrWhiteSpace($AdminPassword)) {
    throw 'Teacher/course moderation is active. Set FT_SMOKE_ADMIN_USERNAME and FT_SMOKE_ADMIN_PASSWORD (or pass -AdminUsername/-AdminPassword) so the smoke flow can approve pending requests.'
  }
  $adminAuth = Invoke-AuthLogin -Username $AdminUsername -Password $AdminPassword
  $token = "$($adminAuth.access_token)"
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Admin login returned empty access_token.'
  }
  $CachedToken.Value = $token
  return $token
}

function Approve-PendingTeacherRegistration {
  param(
    [Parameter(Mandatory = $true)][string]$TeacherUsername,
    [Parameter(Mandatory = $true)][ref]$AdminToken
  )

  $token = Get-AdminAccessToken -CachedToken $AdminToken
  $pendingRequest = $null
  for ($attempt = 0; $attempt -lt 10 -and $null -eq $pendingRequest; $attempt++) {
    $requests = Expand-JsonList (
      Invoke-Json -Method 'GET' -Path '/api/admin/teacher-registration-requests' -AccessToken $token
    )
    $pendingRequest = $requests | Where-Object {
      "$($_.username)" -eq $TeacherUsername -and "$($_.status)" -eq 'pending'
    } | Select-Object -First 1
    if ($null -eq $pendingRequest) {
      Start-Sleep -Seconds 1
    }
  }
  if ($null -eq $pendingRequest) {
    throw "Pending teacher registration request not found for $TeacherUsername."
  }
  [void](Invoke-Json -Method 'POST' -Path "/api/admin/teacher-registration-requests/$($pendingRequest.request_id)/approve" -AccessToken $token)
}

function Approve-PendingCourseUpload {
  param(
    [Parameter(Mandatory = $true)][int64]$CourseId,
    [Parameter(Mandatory = $true)][ref]$AdminToken
  )

  $token = Get-AdminAccessToken -CachedToken $AdminToken
  $pendingRequest = $null
  for ($attempt = 0; $attempt -lt 10 -and $null -eq $pendingRequest; $attempt++) {
    $requests = Expand-JsonList (
      Invoke-Json -Method 'GET' -Path '/api/admin/course-upload-requests' -AccessToken $token
    )
    $pendingRequest = $requests | Where-Object {
      ([int64]$_.course_id -eq $CourseId) -and "$($_.status)" -eq 'pending'
    } | Select-Object -First 1
    if ($null -eq $pendingRequest) {
      Start-Sleep -Seconds 1
    }
  }
  if ($null -eq $pendingRequest) {
    return $false
  }
  [void](Invoke-Json -Method 'POST' -Path "/api/admin/course-upload-requests/$($pendingRequest.request_id)/approve" -AccessToken $token)
  return $true
}

function New-BundleZip {
  param(
    [Parameter(Mandatory = $true)][string]$WorkDir
  )

  $bundleSource = Join-Path $WorkDir 'bundle_source'
  $bundleZip = Join-Path $WorkDir 'course_bundle.zip'
  New-Item -ItemType Directory -Path $bundleSource -Force | Out-Null

  Set-Content -Path (Join-Path $bundleSource 'contents.txt') -Value @(
    '1 Root Concept'
    '1.1 Intro Topic'
  ) -Encoding UTF8
  Set-Content -Path (Join-Path $bundleSource '1_lecture.txt') -Value 'Root lecture text.' -Encoding UTF8
  Set-Content -Path (Join-Path $bundleSource '1.1_lecture.txt') -Value 'Intro lecture text.' -Encoding UTF8

  if (Test-Path $bundleZip) {
    Remove-Item -Path $bundleZip -Force
  }
  Compress-Archive -Path (Join-Path $bundleSource '*') -DestinationPath $bundleZip -CompressionLevel Optimal
  return $bundleZip
}

function Invoke-BundleUpload {
  param(
    [Parameter(Mandatory = $true)][string]$AccessToken,
    [Parameter(Mandatory = $true)][int64]$BundleId,
    [Parameter(Mandatory = $true)][string]$CourseName,
    [Parameter(Mandatory = $true)][string]$BundlePath
  )

  $responseFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ft_upload_" + [guid]::NewGuid().ToString('N') + '.json')
  try {
    $encodedName = [System.Uri]::EscapeDataString($CourseName)
    $uri = "$BaseUrl/api/bundles/upload?bundle_id=$BundleId&course_name=$encodedName"
    $curlArgs = @(
      '-k',
      '-sS',
      '-X', 'POST',
      '-H', "Authorization: Bearer $AccessToken",
      '-F', "bundle=@$BundlePath;type=application/zip",
      $uri,
      '-o', $responseFile,
      '-w', '%{http_code}'
    )
    $statusCodeRaw = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
      throw "curl upload failed with exit code $LASTEXITCODE."
    }
    $statusCode = [int]$statusCodeRaw
    $raw = ''
    if (Test-Path $responseFile) {
      $raw = Get-Content -Path $responseFile -Raw
    }
    if ($statusCode -lt 200 -or $statusCode -ge 300) {
      throw "HTTP $statusCode upload failed: $raw"
    }
    return ($raw | ConvertFrom-Json)
  } finally {
    if (Test-Path $responseFile) {
      Remove-Item -Path $responseFile -Force
    }
  }
}

function Invoke-BundleDownload {
  param(
    [Parameter(Mandatory = $true)][string]$AccessToken,
    [Parameter(Mandatory = $true)][int64]$BundleVersionId,
    [Parameter(Mandatory = $true)][string]$TargetPath
  )

  $headersFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ft_download_headers_" + [guid]::NewGuid().ToString('N') + '.txt')
  try {
    $uri = "$BaseUrl/api/bundles/download?bundle_version_id=$BundleVersionId"
    $targetDir = Split-Path -Path $TargetPath -Parent
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    $curlArgs = @(
      '-k',
      '-sS',
      '-L',
      '-H', "Authorization: Bearer $AccessToken",
      $uri,
      '-D', $headersFile,
      '-o', $TargetPath,
      '-w', '%{http_code}'
    )
    $statusCodeRaw = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
      throw "curl download failed with exit code $LASTEXITCODE."
    }
    $statusCode = [int]$statusCodeRaw
    if ($statusCode -lt 200 -or $statusCode -ge 300) {
      $raw = ''
      if (Test-Path $TargetPath) {
        $raw = Get-Content -Path $TargetPath -Raw
      }
      throw "HTTP $statusCode download failed: $raw"
    }

    $size = (Get-Item -Path $TargetPath).Length
    if ($size -le 0) {
      throw 'Downloaded bundle is empty.'
    }
    return @{
      Path = $TargetPath
      Size = $size
    }
  } finally {
    if (Test-Path $headersFile) {
      Remove-Item -Path $headersFile -Force
    }
  }
}

function Test-BundleImportReady {
  param(
    [Parameter(Mandatory = $true)][string]$BundlePath
  )

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $archive = [System.IO.Compression.ZipFile]::OpenRead($BundlePath)
  try {
    $entryNames = @()
    foreach ($entry in $archive.Entries) {
      if ([string]::IsNullOrWhiteSpace($entry.FullName)) {
        continue
      }
      if ($entry.FullName.EndsWith('/')) {
        continue
      }
      $entryNames += $entry.FullName.Replace('\', '/').TrimStart('/')
    }

    $contentsEntryName = $null
    if ($entryNames -contains 'contents.txt') {
      $contentsEntryName = 'contents.txt'
    } elseif ($entryNames -contains 'context.txt') {
      $contentsEntryName = 'context.txt'
    } else {
      throw 'Bundle missing contents.txt/context.txt.'
    }

    $contentsEntry = $archive.GetEntry($contentsEntryName)
    if ($null -eq $contentsEntry) {
      throw "Bundle entry not found: $contentsEntryName"
    }
    $reader = [System.IO.StreamReader]::new($contentsEntry.Open())
    $contents = $reader.ReadToEnd()
    $reader.Dispose()

    $nodeIds = @()
    foreach ($line in ($contents -split "`r?`n")) {
      $trimmed = $line.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed)) {
        continue
      }
      $match = [regex]::Match($trimmed, '^(\d+(?:\.\d+)*)\s+.+$')
      if (-not $match.Success) {
        throw "Invalid contents line: $trimmed"
      }
      $nodeIds += $match.Groups[1].Value
    }
    if ($nodeIds.Count -eq 0) {
      throw 'Bundle contents has no node IDs.'
    }

    foreach ($nodeId in $nodeIds) {
      $lecturePath = "${nodeId}_lecture.txt"
      $legacyPath = "$nodeId/lecture.txt"
      if (($entryNames -notcontains $lecturePath) -and ($entryNames -notcontains $legacyPath)) {
        throw "Missing lecture file for node ID: $nodeId"
      }
    }
  } finally {
    $archive.Dispose()
  }
}

$suffix = (Get-Date -Format 'yyyyMMddHHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 6))
$teacherUsername = "smoke_teacher_$suffix"
$studentUsername = "smoke_student_$suffix"
$teacherPassword = "Teacher#1!$suffix"
$studentPassword = "Student#1!$suffix"
$teacherEmail = "$teacherUsername@example.com"
$studentEmail = "$studentUsername@example.com"
$courseSubject = "Smoke Algebra $suffix"
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) "family_teacher_smoke_$suffix"
$adminToken = $null

Write-Host "Base URL: $BaseUrl"
Write-Host "Work directory: $workDir"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

try {
  Write-Host 'Registering teacher...'
  $teacherAuth = Invoke-Json -Method 'POST' -Path '/api/auth/register-teacher' -Body @{
    username          = $teacherUsername
    email             = $teacherEmail
    password          = $teacherPassword
    display_name      = "Smoke Teacher $suffix"
    bio               = 'smoke test teacher'
    avatar_url        = ''
    contact           = ''
    contact_published = $false
  }
  $teacherToken = "$($teacherAuth.access_token)"
  if ([string]::IsNullOrWhiteSpace($teacherToken)) {
    throw 'Teacher registration returned empty access_token.'
  }
  $teacherRole = "$($teacherAuth.role)"
  if ($teacherRole -eq 'teacher_pending') {
    Write-Host 'Teacher registration is pending. Approving through admin moderation...'
    Approve-PendingTeacherRegistration -TeacherUsername $teacherUsername -AdminToken ([ref]$adminToken)
    $teacherLogin = Invoke-AuthLogin -Username $teacherUsername -Password $teacherPassword
    $teacherToken = "$($teacherLogin.access_token)"
    $teacherRole = "$($teacherLogin.role)"
    if ([string]::IsNullOrWhiteSpace($teacherToken) -or $teacherRole -ne 'teacher') {
      throw "Teacher approval completed but refreshed login role is '$teacherRole'."
    }
  }

  Write-Host 'Registering student...'
  $studentAuth = Invoke-Json -Method 'POST' -Path '/api/auth/register-student' -Body @{
    username = $studentUsername
    email    = $studentEmail
    password = $studentPassword
  }
  $studentToken = "$($studentAuth.access_token)"
  if ([string]::IsNullOrWhiteSpace($studentToken)) {
    throw 'Student registration returned empty access_token.'
  }

  Write-Host 'Creating teacher course...'
  $createdCourse = Invoke-Json -Method 'POST' -Path '/api/teacher/courses' -AccessToken $teacherToken -Body @{
    subject     = $courseSubject
    grade       = ''
    description = 'Smoke test course.'
  }
  $courseId = [int64]$createdCourse.course_id
  if ($courseId -le 0) {
    throw 'Create course response missing course_id.'
  }

  Write-Host 'Ensuring bundle...'
  $ensureBundle = Invoke-Json -Method 'POST' -Path "/api/teacher/courses/$courseId/bundles" -AccessToken $teacherToken
  $bundleId = [int64]$ensureBundle.bundle_id
  $effectiveCourseId = [int64]$ensureBundle.course_id
  if ($bundleId -le 0 -or $effectiveCourseId -le 0) {
    throw 'Ensure bundle response missing bundle_id/course_id.'
  }

  Write-Host 'Building and uploading bundle...'
  $bundleZip = New-BundleZip -WorkDir $workDir
  $uploadResult = Invoke-BundleUpload -AccessToken $teacherToken -BundleId $bundleId -CourseName $courseSubject -BundlePath $bundleZip
  $bundleVersionId = [int64]$uploadResult.bundle_version_id
  if ($bundleVersionId -le 0) {
    throw 'Upload response missing bundle_version_id.'
  }
  if (Approve-PendingCourseUpload -CourseId $effectiveCourseId -AdminToken ([ref]$adminToken)) {
    Write-Host 'Approved pending course upload through admin moderation.'
  }

  Write-Host 'Publishing course...'
  $publishResult = Invoke-Json -Method 'POST' -Path "/api/teacher/courses/$effectiveCourseId/publish" -AccessToken $teacherToken -Body @{
    visibility = 'public'
  }
  if ("$($publishResult.visibility)" -ne 'public') {
    throw 'Publish response did not confirm public visibility.'
  }

  Write-Host 'Student requesting enrollment...'
  $requestResult = Invoke-Json -Method 'POST' -Path '/api/enrollment-requests' -AccessToken $studentToken -Body @{
    course_id = $effectiveCourseId
    message   = 'Smoke test enrollment request.'
  }
  $requestId = [int64]$requestResult.request_id
  if ($requestId -le 0) {
    throw 'Enrollment request response missing request_id.'
  }

  Write-Host 'Teacher approving enrollment request...'
  $teacherRequests = Invoke-Json -Method 'GET' -Path '/api/teacher/enrollment-requests' -AccessToken $teacherToken
  $pendingRequest = $teacherRequests | Where-Object {
    ([int64]$_.request_id -eq $requestId) -and ($_.status -eq 'pending')
  } | Select-Object -First 1
  if ($null -eq $pendingRequest) {
    throw "Pending enrollment request $requestId not found for teacher."
  }
  [void](Invoke-Json -Method 'POST' -Path "/api/teacher/enrollment-requests/$requestId/approve" -AccessToken $teacherToken)

  Write-Host 'Student fetching enrollment and downloading bundle...'
  $enrollments = Invoke-Json -Method 'GET' -Path '/api/enrollments' -AccessToken $studentToken
  $studentEnrollment = $enrollments | Where-Object {
    ([int64]$_.course_id -eq $effectiveCourseId)
  } | Select-Object -First 1
  if ($null -eq $studentEnrollment) {
    throw "Active enrollment not found for course_id=$effectiveCourseId."
  }
  $latestBundleVersionId = [int64]$studentEnrollment.latest_bundle_version_id
  if ($latestBundleVersionId -le 0) {
    throw 'Student enrollment missing latest_bundle_version_id.'
  }

  $downloadPath = Join-Path $workDir 'downloaded_bundle.zip'
  $downloadResult = Invoke-BundleDownload -AccessToken $studentToken -BundleVersionId $latestBundleVersionId -TargetPath $downloadPath
  Test-BundleImportReady -BundlePath $downloadPath

  $summary = [ordered]@{
    base_url                = $BaseUrl
    teacher_username        = $teacherUsername
    student_username        = $studentUsername
    course_id               = $effectiveCourseId
    bundle_id               = $bundleId
    bundle_version_id       = $latestBundleVersionId
    downloaded_bundle_bytes = [int64]$downloadResult.Size
    status                  = 'ok'
  }
  Write-Host 'Smoke flow completed successfully.'
  $summary | ConvertTo-Json -Depth 5
} finally {
  if (-not $KeepArtifacts.IsPresent -and (Test-Path $workDir)) {
    Remove-Item -Path $workDir -Recurse -Force
  }
}
