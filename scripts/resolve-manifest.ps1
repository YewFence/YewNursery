# scripts/resolve-manifest.ps1
# Resolves the target manifest file from the list of changed files.
# Used by Github Actions workflow.

param (
    [string]$CommentBody,
    [string]$AllChangedFiles
)

$ErrorActionPreference = 'Stop'

# If help command, skip manifest resolution
if ($CommentBody -match '^\s*/help') {
    Write-Host "Help command detected. Skipping manifest resolution."
    "TARGET_MANIFEST=SKIP" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    exit 0
}

# Filter for valid manifest files
$files = @($AllChangedFiles -split ' ' | Where-Object { 
    $_ -match '\.json$' -and 
    $_ -notmatch '\.example\.json$' -and 
    $_ -notmatch '\.template\.json$' 
})

if ($files.Count -eq 0) {
    Write-Error "No valid manifest file found in changes."
    exit 1
}

if ($files.Count -gt 1) {
    Write-Error "Multiple manifest files found: $($files -join ', '). Please modify only one manifest."
    exit 1
}

$target = $files[0]
Write-Host "Target manifest resolved: $target"
"TARGET_MANIFEST=$target" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
