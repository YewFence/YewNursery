function Get-ChangedManifestPath {
    $files = git diff --name-only --diff-filter=ACM origin/main...HEAD -- bucket | Where-Object { $_ -match '^bucket[\\/].+\.json$' }
    if (-not $files) {
        Write-Error "No manifest file found in the changes."
    }
    if ($files -is [array] -and $files.Count -gt 1) {
        Write-Error "Multiple manifest files found in the changes. Please modify one manifest per PR."
    }
    if ($files -is [array]) { return $files[0] }
    return $files
}
