param(
    [ValidateSet('records', 'controls', 'management')]
    [string]$Workflow = 'records',
    [ValidatePattern('^emulator-[0-9]+$')]
    [string]$Device = 'emulator-5554',
    [ValidateRange(1024, 65535)]
    [int]$Port = 8874,
    [switch]$ReleaseOnly,
    [string]$ResumeUsername = '',
    [ValidateSet('manual', 'learning')]
    [string]$ResumeAt = 'manual',
    [string]$ResumeEventRun = ''
)
$ErrorActionPreference = 'Stop'
if ($ReleaseOnly -and $Workflow -ne 'records') {
    throw '-ReleaseOnly is supported only with -Workflow records.'
}
if ($ResumeUsername -and (!$ReleaseOnly -or $ResumeUsername -notmatch '^flow_[0-9]+$')) {
    throw '-ResumeUsername requires the isolated flow_<timestamp> account and -ReleaseOnly.'
}
if ($ResumeAt -eq 'learning' -and $ResumeEventRun -notmatch '^[0-9a-fA-F-]{36}$') {
    throw '-ResumeAt learning requires the prior passed event run id via -ResumeEventRun.'
}
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'android-device.ps1')
Set-SemesterGradleJava
$sdkPath = Join-Path $env:LOCALAPPDATA 'Android/Sdk'
$adbPath = Join-Path $sdkPath 'platform-tools/adb.exe'
$aaptPath = Join-Path $sdkPath 'build-tools/36.0.0/aapt.exe'
$flutterPath = Join-Path $env:USERPROFILE 'flutter/bin/flutter.bat'
$mobilePath = Join-Path $projectRoot 'apps/mobile'
$apkPath = Join-Path $mobilePath 'build/app/outputs/flutter-apk/app-debug.apk'
$outputPath = Join-Path $projectRoot ('output/verification/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-app-' + $Workflow)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

# Start scripts/app_flow_qa_server.py separately. This runner can only talk to
# the disposable local backend; no user's normal package or cloud data is used.
$health = Invoke-RestMethod "http://127.0.0.1:$Port/health"
if ($health.status -ne 'ok' -or $health.database -ne 'sqlite') {
    throw "The disposable local QA server must be running on port $Port."
}
$target = if ($Workflow -eq 'controls') {
    'integration_test/app_controls_test.dart'
} else { 'integration_test/app_workflow_test.dart' }
$defines = @("--dart-define=API_BASE_URL=http://10.0.2.2:$Port", "--dart-define=QA_BACKEND_PORT=$Port")
if ($ReleaseOnly) { $defines += '--dart-define=QA_RELEASE_ONLY=true' }
if ($ResumeUsername) { $defines += "--dart-define=QA_RESUME_USERNAME=$ResumeUsername" }
if ($ResumeUsername) { $defines += "--dart-define=QA_RESUME_AT=$ResumeAt" }
if ($ResumeEventRun) { $defines += "--dart-define=QA_RESUME_EVENT_RUN=$ResumeEventRun" }
if ($Workflow -eq 'management') { $defines += '--dart-define=QA_MANAGEMENT_ONLY=true' }
$previousOutput = $env:NOTICE_UI_OUTPUT
Push-Location $mobilePath
try {
    $priorNativeErrorAction = $ErrorActionPreference
    try {
        # Windows PowerShell treats ordinary native stderr as ErrorRecord.
        # Flutter's mirror banner must be logged, not converted to an abort.
        $ErrorActionPreference = 'Continue'
        & $flutterPath --no-version-check build apk --debug --target-platform=android-x64 -PsemesterosQa=true "--target=$target" @defines *> (Join-Path $outputPath 'build.log')
        $qaBuildExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $priorNativeErrorAction }
    if ($qaBuildExit -ne 0) { throw 'QA APK build failed; see build.log.' }
    $badging = & $aaptPath dump badging $apkPath
    if ($badging[0] -notmatch "name='cn\.semesteros\.semester_os\.qa'") {
        throw 'Refusing to install a non-QA package.'
    }
    & $adbPath -s $Device install -r $apkPath
    if ($LASTEXITCODE -ne 0) { throw 'QA APK installation failed.' }
    # Flutter drive removes its QA package after each run. Grant permissions
    # after installing each new binary, before entering the native UI.
    foreach ($permission in @('RECORD_AUDIO', 'POST_NOTIFICATIONS')) {
        & $adbPath -s $Device shell pm grant cn.semesteros.semester_os.qa "android.permission.$permission"
        if ($LASTEXITCODE -ne 0) { throw "Could not grant $permission to QA package." }
    }
    $env:NOTICE_UI_OUTPUT = $outputPath
    try {
        $ErrorActionPreference = 'Continue'
        & $flutterPath --no-version-check drive --no-pub -d $Device --driver=test_driver/notice_smoke.dart "--target=$target" "--use-application-binary=$apkPath" -PsemesterosQa=true @defines *> (Join-Path $outputPath 'run.log')
        $qaDriveExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $priorNativeErrorAction }
    if ($qaDriveExit -ne 0) { throw 'Native workflow failed; see run.log and failure.png.' }
    $report = Get-Content -LiteralPath (Join-Path $outputPath 'notice-ui-results.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (!$report.workflows -or @($report.workflows | Where-Object { !$_.passed }).Count -gt 0) {
        throw 'The workflow report is missing or contains a failure.'
    }
    Write-Host "Passed $($report.workflows.Count) UI checkpoints. Evidence: $outputPath"
} finally {
    $env:NOTICE_UI_OUTPUT = $previousOutput
    Pop-Location
}
