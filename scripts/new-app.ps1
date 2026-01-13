param (
    [Parameter(Mandatory = $true)]
    [string]$GitHubUrl,
    [string]$CreateShortcut = "false",
    [string]$ReportPath = "pr_body.md"
)

$CreateShortcutBool = [System.Convert]::ToBoolean($CreateShortcut)
$ErrorActionPreference = "Stop"

# --- Helpers ---

function Get-Architecture {
    # Helper to create architecture object safely
    param($Url, $Hash)
    return @{ "64bit" = @{ "url" = $Url; "hash" = $Hash } }
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

function Inspect-Archive {
    param($FilePath, $RepoName)
    
    # Use 7z to list contents
    # -slt: show technical information for each file
    # We just need path and attributes ideally, but simple list is okay
    # `7z l` output is table-like. `7z l -slt` is key-value.
    # Let's use simple list and regex parsing for speed and simplicity.
    
    Write-Host "Inspecting archive: $FilePath"
    
    try {
        $output = 7z l $FilePath
    } catch {
        Write-Warning "7zip failed to read archive. Skipping inspection."
        return $null
    }

    # Parse 7z output to find files
    # Typical line: "2023-01-01 12:00:00 ....A      1024      500  filename.exe"
    # We just want the last column (filename) if it ends in .exe
    
    $exes = @()
    $dirs = @()
    
    foreach ($line in $output) {
        if ($line -match '\.exe$') {
            # Extract filename (simplistic approach: take last token)
            # Better: split by space, take remaining after date/time/attr/size/compressed/name
            # But spaces in filenames make this hard.
            # `7z l -slt` is safer.
        }
    }
    
    # Retry with -slt for robust parsing
    $outputSlt = 7z l -slt $FilePath
    
    $currentPath = ""
    $isDir = $false
    
    $fileList = @()
    
    foreach ($line in $outputSlt) {
        if ($line -match '^Path = (.*)') {
            $currentPath = $Matches[1]
        } elseif ($line -match '^Folder = \+') {
            $isDir = $true
        } elseif ($line -eq "") {
            # Block finished
            if (-not $isDir -and $currentPath) {
                $fileList += $currentPath
            }
            # Reset
            $currentPath = ""
            $isDir = $false
        }
    }
    
    $exeFiles = $fileList | Where-Object { $_ -match '\.exe$' }
    Write-Host "Found $($exeFiles.Count) EXEs."

    $bin = $null
    $fallback = $false
    
    if ($exeFiles.Count -eq 1) {
        $bin = $exeFiles[0]
    } elseif ($exeFiles.Count -gt 1) {
        # Heuristic 1: Match Repo Name
        $bin = $exeFiles | Where-Object { $_ -match "$RepoName\.exe$" } | Select-Object -First 1
        
        # Heuristic 2: Root level exe
        if (-not $bin) {
            $rootExes = $exeFiles | Where-Object { $_ -notmatch '[/\\]' }
            if ($rootExes.Count -eq 1) {
                $bin = $rootExes[0]
                $fallback = $true
            }
        }
    }
    
    # Basic Extract Dir logic: check if all files start with the same directory
    $extractDir = $null
    if ($fileList.Count -gt 0) {
        $firstSlash = $fileList[0].IndexOfAny(@('/', '\'))
        if ($firstSlash -gt 0) {
            $potentialRoot = $fileList[0].Substring(0, $firstSlash)
            $allMatch = $true
            foreach ($f in $fileList) {
                if (-not $f.StartsWith($potentialRoot)) { $allMatch = $false; break }
            }
            if ($allMatch) { $extractDir = $potentialRoot }
        }
    }

    return @{ Bin = $bin; Fallback = $fallback; ExtractDir = $extractDir }
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
$BinFallback = $false

if ($Asset.name -match "\.(zip|7z|rar|gz|tgz)$") {
    $info = Inspect-Archive -FilePath $TempFile -RepoName $Repo
    if ($info) {
        $BinName = $info.Bin
        $ExtractDirName = $info.ExtractDir
        $BinFallback = $info.Fallback
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
$proc = Start-Process -FilePath "jq" -ArgumentList $jqArgs -NoNewWindow -PassThru -RedirectStandardOutput $ManifestPath
$proc.WaitForExit()

if ($proc.ExitCode -ne 0) {
    Throw "jq failed to generate manifest"
}

Write-Host "Manifest saved to $ManifestPath"

# 8. Report
$BinStatus = if ($BinName) { "⚠️ Suggested" } else { "⭕ Missing" }
$BinValue = if ($BinName) { "``$BinName``" + $(if ($BinFallback) { " (Fallback)" } else { "" }) } else { "Manual fill" }

$Report = @"
## Automatic App Manifest Generation

**Repository**: [$Owner/$Repo]($Homepage)
**Version**: $Version
**License**: $License
**Description**: $Description

### Detection Status

| Field | Status | Value |
|-------|--------|-------|
| ``version`` | ✅ Detected | $Version |
| ``architecture`` | ✅ Detected | 64bit |
| ``hash`` | ✅ Calculated | $Hash |
| ``bin`` | $BinStatus | $BinValue |
| ``shortcuts`` | $(if ($CreateShortcutBool -and $BinName) { "✅ Generated" } else { "⭕ Missing" }) | |
| ``checkver`` | ✅ Configured | ``github`` |

### ChatOps Available
- `/set-bin "app.exe"` or `/set-bin "app.exe" "alias"`
- `/set-shortcut "app.exe" "Name"`
- `/set-persist "data"`
- `/set-key "description" "New desc"`
"@

$Report | Set-Content $ReportPath
