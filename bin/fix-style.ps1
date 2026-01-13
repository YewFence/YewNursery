param(
    [switch]$Fix = $true,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$TargetFiles
)

$Extensions = @(".ps1", ".psm1", ".json", ".yml", ".yaml", ".md", ".txt", ".js")
$Ignore = @(".git", "scoop_core")

if ($TargetFiles) {
    $Files = $TargetFiles | ForEach-Object {
        if (Test-Path $_ -PathType Leaf) {
            Get-Item $_
        } elseif (Test-Path $_ -PathType Container) {
            Get-ChildItem -Path $_ -Recurse -File | Where-Object {
                $_.FullName -notmatch "\\.git\\" -and
                $_.FullName -notmatch "\\scoop_core\\"
            }
        }
    } | Where-Object {
        $ext = $_.Extension
        $Extensions -contains $ext
    }
} else {
    $Files = Get-ChildItem -Path "$PSScriptRoot/.." -Recurse -File | Where-Object {
        $ext = $_.Extension
        $Extensions -contains $ext -and
        $_.FullName -notmatch "\\.git\\" -and
        $_.FullName -notmatch "\\scoop_core\\"
    }
}

$Failed = $false

foreach ($File in $Files) {
    $Content = Get-Content -LiteralPath $File.FullName -Raw

    if (-not $Content) { continue }

    # Normalize content: remove trailing whitespace per line, ensure single newline at end
    $NewContent = $Content -replace "(?m)[ \t]+(?=\r?$)", ""
    $NewContent = $NewContent.TrimEnd() + [Environment]::NewLine

    if ($Content -ne $NewContent) {
        Write-Host "Style issues found (trailing whitespace or EOF): $($File.FullName)" -ForegroundColor Yellow
        $Failed = $true

        if ($Fix) {
            $NewContent | Set-Content -LiteralPath $File.FullName -NoNewline -Encoding UTF8
            Write-Host "  Fixed." -ForegroundColor Green
        }
    }
}

if ($Failed -and -not $Fix) {
    exit 1
}

Write-Host "Style check complete." -ForegroundColor Green
