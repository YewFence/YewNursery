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

    # 1. Capture OLD state
    $manifestPath = $null
    $oldContent = ""
    try {
        # Try to resolve manifest path similar to how pr-chatops does,
        # but here we just do a quick guess for before-state or let pr-chatops handle validation.
        # Ideally, we should unify this logic.
        # For now, let's find the changed JSON file first.
        $files = git diff --name-only --diff-filter=ACM origin/main...HEAD -- bucket | Where-Object { $_ -match '^bucket[\\/].+\.json$' }
        if ($files -is [array] -and $files.Count -gt 1) {
            Write-Error "Multiple manifest files found in the changes. Please modify one manifest per PR."
        }
        if ($files -is [array]) { $files = $files[0] }

        if ($files -and (Test-Path $files)) {
            $manifestPath = $files
            $oldContent = Get-Content -Raw $manifestPath -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Could not capture pre-execution state: $_"
    }

    # 2. Execute script and capture ALL output (streams *>&1) to log file
    # We use try/catch to ensure we capture the exit code correctly while Tee-Object runs
    try {
        & ./scripts/pr-chatops.ps1 -Command $cmd -ArgsLine $argsLine *>&1 | Tee-Object -FilePath "chatops.log"
        if ($LASTEXITCODE -ne 0) { throw "Script failed with exit code $LASTEXITCODE" }
    } catch {
        Write-Error "ChatOps execution failed: $_"
        exit 1
    }

    # 3. Generate Report if successful
    if ($manifestPath -and (Test-Path $manifestPath)) {
        Write-Host "Generating report for $manifestPath..."
        try {
             # We pass the OLD content as a string.
             # Note: PowerShell argument passing of multiline strings can be tricky,
             # so we might pass it via file or Base64 if it was complex, but direct string usually works for JSON.
             # Alternatively, we just pass the path and let the report script read the NEW content,
             # but we need to pass the OLD content somehow.

             # Let's save old content to a temp file to be safe
             $oldFile = "old_manifest.tmp"
             if ($oldContent) {
                $oldContent | Out-File -FilePath $oldFile -Encoding utf8
                $oldContentRaw = Get-Content -Raw $oldFile
             } else {
                $oldContentRaw = ""
             }

             ./scripts/generate-report.ps1 -ManifestPath $manifestPath -OldContentString $oldContentRaw
        } catch {
             Write-Warning "Report generation failed: $_"
        }
    }

} else {
    Write-Warning "No command found in comment body."
}
