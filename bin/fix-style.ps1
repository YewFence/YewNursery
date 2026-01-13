param(
    [switch]$Fix = $true
)

$Extensions = @(".ps1", ".psm1", ".json", ".yml", ".yaml", ".md", ".txt")
$Ignore = @(".git", "scoop_core")

$Files = Get-ChildItem -Path "$PSScriptRoot/.." -Recurse -File | Where-Object {
    $ext = $_.Extension
    $Extensions -contains $ext -and
    $_.FullName -notmatch "\\.git\\" -and
    $_.FullName -notmatch "\\scoop_core\\"
}

$Failed = $false

foreach ($File in $Files) {
    $Content = Get-Content -LiteralPath $File.FullName -Raw

    if (-not $Content) { continue }

    # Check for trailing whitespace (per line)
    if ($Content -match "(?m)[ \t]+$") {
        Write-Host "Trailing whitespace found: $($File.FullName)" -ForegroundColor Yellow
        $Failed = $true

        if ($Fix) {
            $NewContent = $Content -replace "(?m)[ \t]+$", ""
            # Ensure single newline at end
            $NewContent = $NewContent.TrimEnd() + [Environment]::NewLine
            $NewContent | Set-Content -LiteralPath $File.FullName -NoNewline -Encoding UTF8
            Write-Host "  Fixed." -ForegroundColor Green
        }
    }

    # Check for file ending with newline
    # Note: Get-Content -Raw usually preserves it, but logic above .TrimEnd() + NewLine ensures it.
}

if ($Failed -and -not $Fix) {
    exit 1
}

Write-Host "Style check complete." -ForegroundColor Green
