param (
    [Parameter(Mandatory = $true)]
    [string]$GitHubUrl,
    [string]$CreateShortcut = "false",
    [string]$ReportPath = "pr_body.md"
)

$CreateShortcutBool = [System.Convert]::ToBoolean($CreateShortcut)
$ErrorActionPreference = "Stop"

# --- Helpers ---

function Render-Template {
    param(
        [string]$Path,
        [hashtable]$Data
    )
    if (-not (Test-Path $Path)) { Throw "Template not found: $Path" }
    # Use UTF8 encoding to match standard MD files
    $Content = Get-Content -Path $Path -Raw -Encoding UTF8
    foreach ($key in $Data.Keys) {
        $Token = "{{" + $key + "}}"
        $Value = if ($null -ne $Data[$key]) { $Data[$key] } else { "" }
        # Simple string replacement
        $Content = $Content.Replace($Token, $Value)
    }
    return $Content
}

function Get-MatchingAsset {
    param ($Assets)

    # 1. Filter for 64-bit architectures
    $candidates = $Assets | Where-Object {
        ($_.name -match "64" -or $_.name -match "amd64" -or $_.name -match "x86_64") -and
        ($_.name -notmatch "arm64" -and $_.name -notmatch "aarch64")
    }

    if (-not $candidates) {
        Write-Warning "No explicit 64-bit assets found. Checking all assets..."
        $candidates = $Assets
    }

    # 2. Exclude non-Windows platforms
    $nonWindows = "linux", "macos", "darwin", "android", "ubuntu", "debian", "fedora", "freebsd"
    $candidates = $candidates | Where-Object {
        $name = $_.name.ToLower()
        $isNonWindows = $false
        foreach ($kw in $nonWindows) {
            if ($name -match $kw) { $isNonWindows = $true; break }
        }
        -not $isNonWindows
    }

    if (-not $candidates) {
        Write-Warning "No suitable candidates found after filtering non-Windows assets."
        return $null
    }

    # 3. Prioritize "windows" keyword
    $winCandidates = $candidates | Where-Object { $_.name -match "win" }
    $selectionPool = if ($winCandidates) { $winCandidates } else { $candidates }

    # 4. Select by extension priority
    # Added explicit support for more formats thanks to 7zip
    $priority = @("zip", "7z", "tar.gz", "tgz", "rar", "exe", "msi")

    foreach ($ext in $priority) {
        $match = $selectionPool | Where-Object { $_.name -match "\.$ext$" } | Select-Object -First 1
        if ($match) { return $match }
    }

    return $null
}



# --- Main Logic ---

# 1. Parse URL
if ($GitHubUrl -match "github\.com/([^/]+)/([^/]+)") {
    $Owner = $Matches[1]
    $Repo = $Matches[2] -replace "\.git$", ""
} else {
    Throw "Invalid GitHub URL."
}

# 2. Fetch API
$Headers = @{}
if ($env:GITHUB_TOKEN) { $Headers["Authorization"] = "token $env:GITHUB_TOKEN" }
$ReleaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest" -Headers $Headers
$RepoInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo" -Headers $Headers

# 3. Extract Meta
$Version = $ReleaseInfo.tag_name -replace "^v", ""
$Description = if ($RepoInfo.description) { $RepoInfo.description } else { "Description for $Repo" }
$Homepage = $RepoInfo.html_url
$License = if ($RepoInfo.license) { $RepoInfo.license.spdx_id } else { "Unknown" }

# 4. Find Asset
$Asset = Get-MatchingAsset -Assets $ReleaseInfo.assets
if (-not $Asset) { Throw "No suitable asset found." }

Write-Host "Selected: $($Asset.name)"
Write-Host "URL: $($Asset.browser_download_url)"

# 5. Download & Hash
$TempFile = Join-Path $env:TEMP $Asset.name
Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $TempFile
$Hash = (Get-FileHash $TempFile -Algorithm SHA256).Hash

# 6. Inspect (Bin/ExtractDir)
$BinName = $null
$ExtractDirName = $null
$FileTree = ""
$CandidatesList = @()

if ($Asset.name -match "\.(zip|7z|rar|gz|tgz)$") {
    $FindBinScript = Join-Path $PSScriptRoot "find-bin.ps1"
    Write-Host "Running analysis script: $FindBinScript"

    if (Test-Path $FindBinScript) {
        $ScanResult = & $FindBinScript -FilePath $TempFile -AppName $Repo

        if ($ScanResult) {
            $BinName = $ScanResult.Recommended
            $ExtractDirName = $ScanResult.ExtractDir
            $FileTree = $ScanResult.Tree
            $CandidatesList = $ScanResult.Candidates
        }
    } else {
        Write-Warning "find-bin.ps1 script not found at $FindBinScript"
    }
} elseif ($Asset.name -match "\.exe$") {
    $BinName = $Asset.name
}

# Cleanup
Remove-Item $TempFile -Force

# 7. Construct JSON using JQ
$AutoUpdateUrl = $Asset.browser_download_url -replace $Version, "`$version"
if ($ExtractDirName) {
    $AutoExtractDir = $ExtractDirName -replace $Version, "`$version"
}

# Base JSON Template
# We pass basic types as args, but complex nested objects we construct inside jq query
# to avoid escaping hell.

$jqFilter = @'
{
    version: $version,
    description: $desc,
    homepage: $homepage,
    license: $license,
    architecture: {
        "64bit": {
            url: $url,
            hash: $hash
        }
    },
    checkver: "github",
    autoupdate: {
        architecture: {
            "64bit": {
                url: $autoupdate
            }
        }
    }
}
'@

# Add optional fields dynamically
if ($BinName) {
    $jqFilter += ' | .bin = $bin'

    if ($CreateShortcutBool) {
        # Shortcuts is [[bin, repo]]
        $jqFilter += ' | .shortcuts = [[$bin, $repo]]'
    }
}

if ($ExtractDirName) {
    $jqFilter += ' | .extract_dir = $extract_dir'
    # Update autoupdate extract_dir if needed
    # Note: modifying nested autoupdate path
    $jqFilter += ' | .autoupdate.architecture["64bit"].extract_dir = $auto_extract'
}

# File Path
$ManifestPath = Join-Path "bucket" "$Repo.json"

# Execute jq
# Note: passing all potential args, even if null/empty, jq handles them as null string or we handle logic in filter
# Actually simpler to just pass them all.

$jqArgs = @(
    "--null-input",
    "--arg", "version", $Version,
    "--arg", "desc", $Description,
    "--arg", "homepage", $Homepage,
    "--arg", "license", $License,
    "--arg", "url", $Asset.browser_download_url,
    "--arg", "hash", $Hash,
    "--arg", "autoupdate", $AutoUpdateUrl
)

if ($BinName) { $jqArgs += "--arg", "bin", $BinName }
if ($Repo) { $jqArgs += "--arg", "repo", $Repo }
if ($ExtractDirName) { $jqArgs += "--arg", "extract_dir", $ExtractDirName }
if ($AutoExtractDir) { $jqArgs += "--arg", "auto_extract", $AutoExtractDir }

$jqArgs += $jqFilter

# Run jq and redirect to file
$jqOutput = & jq @jqArgs $jqFilter
if ($LASTEXITCODE -ne 0) {
    Throw "jq failed to generate manifest"
}

$jqOutput | Set-Content -Path $ManifestPath -Encoding UTF8

Write-Host "Manifest saved to $ManifestPath"

# 8. Report
$BinStatus = if ($BinName) { "[SUGGESTED]" } else { "[MISSING]" }
$BinValue = if ($BinName) { "``$BinName``" } else { "Manual fill" }

# Format candidates for report
$CandidatesStr = ""
if ($CandidatesList -and $CandidatesList.Count -gt 0) {
    $c = 1
    foreach ($cand in $CandidatesList) {
        $CandidatesStr += "$c. $cand`n"
        $c++
    }
} else {
    $CandidatesStr = "No candidates found."
}

$ShortcutStatus = if ($CreateShortcutBool -and $BinName) { "[GENERATED]" } else { "[MISSING]" }

$TemplateData = @{
    "Owner"          = $Owner
    "Repo"           = $Repo
    "Homepage"       = $Homepage
    "Version"        = $Version
    "License"        = $License
    "Description"    = $Description
    "Hash"           = $Hash
    "BinStatus"      = $BinStatus
    "BinValue"       = $BinValue
    "ShortcutStatus" = $ShortcutStatus
    "FileTree"       = $FileTree
    "CandidatesStr"  = $CandidatesStr
}

$TemplatePath = Join-Path $PSScriptRoot "templates\new-app-report.md"
Write-Host "Rendering template from: $TemplatePath"

$Report = Render-Template -Path $TemplatePath -Data $TemplateData

$Report | Set-Content $ReportPath -Encoding UTF8
