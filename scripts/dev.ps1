param(
    [ValidateSet('Api', 'Android', 'Test')]
    [string]$Action = 'Api',
    [string]$Device = 'auto',
    [string]$Emulator = 'Medium_Phone_33',
    [ValidateRange(10, 600)][int]$WaitSeconds = 150
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

function Check-Exit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit $LASTEXITCODE)." }
}

if ($Action -eq 'Android') {
    . (Join-Path $PSScriptRoot 'android-device.ps1')
    Set-SemesterGradleJava
    $resolvedDevice = Resolve-SemesterAndroidDevice -ProjectRoot $projectRoot -Device $Device -Emulator $Emulator -WaitSeconds $WaitSeconds
    Push-Location apps/mobile
    try {
        & flutter --no-version-check pub get
        Check-Exit 'Flutter dependencies'
        & flutter --no-version-check run --no-pub -d $resolvedDevice
        Check-Exit 'Android app'
    } finally { Pop-Location }
    exit
}

if (!(Test-Path -LiteralPath '.env')) {
    $localPassword = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLowerInvariant()
    @("POSTGRES_PASSWORD=$localPassword", "DATABASE_URL=postgresql+psycopg://semesteros:$localPassword@127.0.0.1:55439/semesteros") |
        Set-Content -LiteralPath '.env' -Encoding utf8
}
Get-Content -LiteralPath '.env' | ForEach-Object {
    if ($_ -match '^DATABASE_URL=(.+)$') { $env:DATABASE_URL = $Matches[1] }
}
if (!$env:DATABASE_URL) { throw 'DATABASE_URL is missing from .env.' }

& docker compose --env-file .env -f deploy/compose.yaml up -d --wait db
Check-Exit 'PostgreSQL (start Docker Desktop first)'

$pythonPath = Join-Path $projectRoot 'services/api/.venv/Scripts/python.exe'
if (!(Test-Path -LiteralPath $pythonPath)) {
    & python -m venv services/api/.venv
    Check-Exit 'Python virtual environment'
}
& $pythonPath -m pip install -r services/api/requirements.lock
Check-Exit 'Python dependencies'

Push-Location services/api
try {
    & $pythonPath -m alembic upgrade head
    Check-Exit 'Database migrations'
    if ($Action -eq 'Api') {
        & $pythonPath -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8871
        Check-Exit 'API server'
    } else {
        $env:POSTGRES_TEST_URL = $env:DATABASE_URL
        & $pythonPath -m pytest -q
        Check-Exit 'PostgreSQL tests'
    }
} finally { Pop-Location }

if ($Action -eq 'Test') {
    if (!(Get-Command node -ErrorAction SilentlyContinue)) {
        throw '教务JavaScript适配回归需要Node.js 18或以上版本。'
    }
    & node --test apps/mobile/test/haut_reader_test.cjs
    Check-Exit 'School reader JavaScript tests'
    Push-Location apps/mobile
    try {
        & flutter --no-version-check test --no-pub
        Check-Exit 'Flutter tests'
        & flutter --no-version-check analyze --no-pub
        Check-Exit 'Flutter analysis'
    } finally { Pop-Location }
}
