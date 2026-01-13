function Get-ChangedManifestPath {
    $baseRef = if ($env:CHAT_BASE_REF) { $env:CHAT_BASE_REF } else { "origin/main" }
    Write-Host "[DEBUG] BaseRef: $baseRef"
    $rawFiles = git diff --name-only --diff-filter=ACM "$baseRef...HEAD" -- bucket
    Write-Host "[DEBUG] Raw Diff: $($rawFiles -join ', ')"
    $files = $rawFiles | Where-Object { $_ -match '^bucket[\\/].+\.json$' }
    Write-Host "[DEBUG] Filtered Files: $($files -join ', ')"
    if (-not $files) {
        Write-Error "No manifest file found in the changes."
    }
    if ($files -is [array] -and $files.Count -gt 1) {
        Write-Error "Multiple manifest files found in the changes. Please modify one manifest per PR."
    }
    if ($files -is [array]) { return $files[0] }
    return $files
}
