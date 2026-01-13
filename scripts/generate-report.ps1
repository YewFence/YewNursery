# scripts/generate-report.ps1
param (
    [string]$ManifestPath,
    [string]$OldContentString
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ManifestPath)) {
    Write-Error "Manifest file not found: $ManifestPath"
    exit 1
}

$newJson = Get-Content -Raw $ManifestPath | ConvertFrom-Json
$oldJson = $null
if (-not [string]::IsNullOrWhiteSpace($OldContentString)) {
    try {
        $oldJson = $OldContentString | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to parse old JSON content for diff."
    }
}

# Define keys to display
$keys = @("version", "description", "license", "homepage", "bin", "shortcuts", "persist", "checkver", "autoupdate")

$rows = @()

foreach ($key in $keys) {
    $newVal = $newJson.$key
    $oldVal = if ($oldJson) { $oldJson.$key } else { $null }

    # Convert to JSON string for comparison and display (compact)
    $newValStr = if ($null -ne $newVal) { ConvertTo-Json $newVal -Compress -Depth 10 } else { "*(null)*" }
    $oldValStr = if ($null -ne $oldVal) { ConvertTo-Json $oldVal -Compress -Depth 10 } else { "*(null)*" }

    # Clean up JSON formatting for table display (escape pipes, etc if needed)
    # Basic markdown escaping for table
    $displayVal = $newValStr -replace '\|', '\|'

    $statusIcon = ""
    $styleKey = "`$key`"
    
    # Check modification
    if ($oldJson -and $newValStr -ne $oldValStr) {
        $statusIcon = "✨ **Updated**"
        $styleKey = "**$key**"
        $displayVal = "**$displayVal**"
    } elseif (-not $oldJson) {
        # Initial or no old content provided
        $statusIcon = ""
    } elseif ($newValStr -eq "*(null)*") {
         $statusIcon = "⚪ *Empty*"
    }

    # Only add row if value exists or was modified
    if ($newValStr -ne "*(null)*" -or $statusIcon -match "Updated") {
         $rows += "| $styleKey | $statusIcon | $displayVal |"
    }
}

$fileName = Split-Path $ManifestPath -Leaf

$md = @"
### ✅ ChatOps Applied
**Manifest**: ``$fileName``

| Field | Status | Current Value |
| :--- | :--- | :--- |
$($rows -join "`n")

"@

$md | Out-File -FilePath "chatops-report.md" -Encoding utf8
Write-Host "Report generated: chatops-report.md"
