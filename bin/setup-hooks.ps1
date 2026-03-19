$ErrorActionPreference = 'Stop'

$GitDir = "$PSScriptRoot/../.git"
$HookDir = "$GitDir/hooks"
$SourceHook = "$PSScriptRoot/hooks/pre-commit"

if (-not (Test-Path $GitDir)) {
    Write-Warning "This directory is not a git repository root (no .git folder found)."
    exit 1
}

if (-not (Test-Path $HookDir)) {
    New-Item -Path $HookDir -ItemType Directory | Out-Null
}

Copy-Item $SourceHook "$HookDir/pre-commit" -Force
Write-Host "✅ Git hooks installed successfully to .git/hooks/" -ForegroundColor Green
Write-Host "   Style checks will now run before every commit." -ForegroundColor Gray
