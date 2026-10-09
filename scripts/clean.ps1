param(
    [switch]$Apply,
    [switch]$DeveloperCaches,
    [switch]$KeepCloseout
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$rootPrefix = $projectRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar

function Remove-GeneratedPath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (!$absolute.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Cleanup target escaped the project: $absolute"
    }
    if (!(Test-Path -LiteralPath $absolute)) { return }
    $entry = Get-Item -LiteralPath $absolute -Force
    $relative = [IO.Path]::GetRelativePath($projectRoot, $absolute)
    if (!$Apply) { Write-Output "Would remove: $relative"; return }
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Remove-Item -LiteralPath $absolute -Force
    } else {
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
    Write-Output "Removed: $relative"
}

# Never removes Git, source, signing keys, .env, or original local media.
$outputRoot = Join-Path $projectRoot 'output'
if (Test-Path -LiteralPath $outputRoot) {
    foreach ($entry in Get-ChildItem -LiteralPath $outputRoot -Force) {
        if ($entry.Name -in @('apk', 'release')) { continue }
        if ($KeepCloseout -and $entry.Name -eq 'closeout') { continue }
        Remove-GeneratedPath $entry.FullName
    }
}
foreach ($relative in @(
    'apps/mobile/build', 'apps/mobile/.dart_tool',
    'apps/mobile/android/.gradle', 'apps/mobile/android/.kotlin',
    'apps/mobile/android/app/.cxx', 'apps/mobile/android/app/build',
    'services/api/.pytest_cache', 'scripts/__pycache__',
    'services/api/app/__pycache__', 'services/api/tests/__pycache__',
    'services/api/alembic/__pycache__', 'services/api/alembic/versions/__pycache__',
    'artifacts/feedback-plan-semester'
)) {
    Remove-GeneratedPath (Join-Path $projectRoot $relative)
}
if ($DeveloperCaches) {
    foreach ($relative in @('services/api/.venv', '.local-data/models')) {
        Remove-GeneratedPath (Join-Path $projectRoot $relative)
    }
}
if (Test-Path -LiteralPath (Join-Path $projectRoot 'tmp')) {
    foreach ($entry in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tmp') -Force) {
        try { Remove-GeneratedPath $entry.FullName }
        catch { Write-Warning "Still open by a running process: $($entry.Name)" }
    }
}
