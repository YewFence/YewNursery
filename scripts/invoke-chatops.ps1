# scripts/invoke-chatops.ps1
# Wrapper script to invoke pr-chatops.ps1 based on Comment Body

$ErrorActionPreference = 'Stop'

$body = $env:COMMENT_BODY
if (-not $body) {
    Write-Error "COMMENT_BODY environment variable is empty."
    exit 1
}

# Extract command and args. Assuming one command per comment line or just first line.
# We take the first line that starts with /
$line = $body -split "`n" | Where-Object { $_ -match '^/' } | Select-Object -First 1

$cmd = $null
$argsLine = ""

if ($line -match '^(\/[^\s]+)\s+(.*)$') {
    $cmd = $Matches[1]
    $argsLine = $Matches[2]
} elseif ($line -match '^(\/[^\s]+)$') {
    $cmd = $Matches[1]
    $argsLine = ""
}

if ($cmd) {
    Write-Host "Executing: $cmd $argsLine"
    
    # Execute script and capture ALL output (streams *>&1) to log file
    # We use try/catch to ensure we capture the exit code correctly while Tee-Object runs
    try {
        & ./scripts/pr-chatops.ps1 -Command $cmd -ArgsLine $argsLine *>&1 | Tee-Object -FilePath "chatops.log"
        if ($LASTEXITCODE -ne 0) { throw "Script failed with exit code $LASTEXITCODE" }
    } catch {
        Write-Error "ChatOps execution failed: $_"
        exit 1
    }
} else {
    Write-Warning "No command found in comment body."
}
