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

    if ($cmd -eq "/help") {
        Write-Host "Help command detected. Generating guide report."
        $guidePath = Join-Path $PSScriptRoot "templates\chatops-usage-guide.md"
        if (Test-Path $guidePath) {
            Get-Content $guidePath | Out-File "chatops-report.md" -Encoding utf8
            exit 0
        } else {
            Write-Error "Guide template not found at $guidePath"
            exit 1
        }
    }

    # 1. Capture OLD state
    $manifestPath = $env:TARGET_MANIFEST
    if (-not $manifestPath) {
        Write-Error "TARGET_MANIFEST environment variable not found."
        exit 1
    }
    
    Write-Host "Using target manifest: $manifestPath"
    
    $oldContent = ""
    try {
        if (Test-Path $manifestPath) {
            $oldContent = Get-Content -Raw $manifestPath -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Could not capture pre-execution state: $_"
    }

    # 2. Execute script and capture ALL output (streams *>&1) to log file
    # We use try/catch to ensure we capture the exit code correctly while Tee-Object runs
    $scriptFailed = $false
    try {
        & ./scripts/pr-chatops.ps1 -Command $cmd -ArgsLine $argsLine -ManifestPath $manifestPath *>&1 | Tee-Object -FilePath "chatops.log"
        # Check both $LASTEXITCODE and $? to catch all failure scenarios
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { 
            $scriptFailed = $true
            throw "Script failed with exit code $LASTEXITCODE" 
        }
        if (-not $?) {
            $scriptFailed = $true
            throw "Script execution failed"
        }
    } catch {
        $scriptFailed = $true
        Write-Error "ChatOps execution failed: $_"
    }
    
    if ($scriptFailed) {
        exit 1
    }

    # 3. Generate Report if successful
    if ($manifestPath -and (Test-Path $manifestPath)) {
        Write-Host "Generating report for $manifestPath..."
        try {
             ./scripts/generate-report.ps1 -ManifestPath $manifestPath -OldContentString $oldContent
        } catch {
             Write-Warning "Report generation failed: $_"
        }
    }

} else {
    Write-Warning "No command found in comment body."
}
