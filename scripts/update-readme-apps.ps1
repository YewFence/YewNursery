param (
    [string]$ReadmePath = "README.md",
    [string]$BucketDir  = "bucket"
)

$startMarker = "<!-- APPS_LIST_START -->"
$endMarker   = "<!-- APPS_LIST_END -->"

$rows = Get-ChildItem "$BucketDir/*.json" |
    Where-Object { $_.Name -notmatch "template|example" } |
    Sort-Object Name |
    ForEach-Object {
        $data     = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $name     = $_.BaseName
        $homepage = $data.homepage
        $desc     = $data.description
        $lic      = if ($data.license -is [string]) { $data.license } else { $data.license.identifier }
        $link     = if ($homepage) { "[$name]($homepage)" } else { $name }
        "| $link | $desc | ``$lic`` |"
    }

$table = @(
    "## 收录应用",
    "",
    "| 应用 | 简介 | LICENSE |",
    "|------|------|---------|",
    ($rows -join "`n")
) -join "`n"

$section = "$startMarker`n$table`n$endMarker"

$readme = Get-Content $ReadmePath -Raw -Encoding UTF8
if ($readme -match [regex]::Escape($startMarker)) {
    $readme = [regex]::Replace(
        $readme,
        ([regex]::Escape($startMarker) + "[\s\S]*?" + [regex]::Escape($endMarker)),
        $section
    )
} else {
    $readme = $readme.TrimEnd() + "`n`n$section`n"
}

Set-Content $ReadmePath -Value $readme -Encoding UTF8 -NoNewline
Write-Host "README updated successfully"
