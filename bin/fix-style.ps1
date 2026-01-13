param(
    [bool]$Fix = $true,
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

    # Check for UTF-8 BOM
    $HasBom = $false
    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $Bytes = Get-Content -LiteralPath $File.FullName -AsByteStream -TotalCount 3 -ErrorAction Stop
        } else {
            $Bytes = Get-Content -LiteralPath $File.FullName -Encoding Byte -TotalCount 3 -ErrorAction Stop
        }
        if ($Bytes.Count -eq 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
            $HasBom = $true
        }
    } catch {
        # Ignore read errors for BOM check
    }

    # Normalize content: remove trailing whitespace per line, ensure single newline at end
    $NewContent = $Content -replace "(?m)[ \t]+(?=\r?$)", ""
    # Normalize to CRLF
    $NewContent = $NewContent -replace "(?<!\r)\n", "`r`n"
    $NewContent = $NewContent.TrimEnd() + [Environment]::NewLine

    if (($Content -ne $NewContent) -or $HasBom) {
        if ($HasBom) {
            Write-Host "UTF-8 BOM found: $($File.FullName)" -ForegroundColor Yellow
        }
        if ($Content -ne $NewContent) {
            Write-Host "Style issues found (trailing whitespace or EOF): $($File.FullName)" -ForegroundColor Yellow
        }

        $Failed = $true

        if ($Fix) {
            # Use .NET to write UTF-8 without BOM, compatible with both WinPS and PS Core
            $Utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($File.FullName, $NewContent, $Utf8NoBom)
            Write-Host "  Fixed." -ForegroundColor Green
        }
    }
}

if ($Failed -and -not $Fix) {
    exit 1
}

Write-Host "Style check complete." -ForegroundColor Green
