param (
    [Parameter(Mandatory = $true)]
    [string]$GitHubUrl,
    [string]$CreateShortcut = "false",
    [string]$ReportPath = "pr_body.md"
)

$CreateShortcutBool = [System.Convert]::ToBoolean($CreateShortcut)

# Set up error handling
$ErrorActionPreference = "Stop"

# Helper function to get matching asset
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
    # Common Linux/Mac keywords
    $nonWindows = "linux", "macos", "darwin", "android", "ubuntu", "debian", "fedora", "freebsd"
    $candidates = $candidates | Where-Object {
        $name = $_.name.ToLower()
        # Return true if NO non-windows keyword matches
        $isNonWindows = $false
        foreach ($kw in $nonWindows) {
            if ($name -match $kw) {
                $isNonWindows = $true;
                break
            }
        }
        -not $isNonWindows
    }

    if (-not $candidates) {
        Write-Warning "No suitable candidates found after filtering non-Windows assets."
        return $null
    }

    # 3. Prioritize "windows" keyword
    $winCandidates = $candidates | Where-Object { $_.name -match "win" }

    # Use winCandidates if any, otherwise fall back to filtered candidates (generic names)
    if ($winCandidates) {
        $selectionPool = $winCandidates
    }
    else {
        $selectionPool = $candidates
    }

    # 4. Select by extension priority
    # Priority: zip > exe > msi > 7z > tar.gz
    $priority = @("zip", "exe", "msi", "7z", "tar.gz")

    foreach ($ext in $priority) {
        $match = $selectionPool | Where-Object { $_.name -match "\.$ext$" } | Select-Object -First 1
        if ($match) { return $match }
    }

    return $null
}

# 1. Parse GitHub URL
if ($GitHubUrl -match "github\.com/([^/]+)/([^/]+)") {
    $Owner = $Matches[1]
    $Repo = $Matches[2] -replace "\.git$", ""
}
else {
    Throw "Invalid GitHub URL format."
}

Write-Host "Fetching info for $Owner/$Repo..."

# 2. Fetch API Data
$Headers = @{}
if ($env:GITHUB_TOKEN) {
    $Headers["Authorization"] = "token $env:GITHUB_TOKEN"
}

try {
    $RepoInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo" -Headers $Headers
    $ReleaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest" -Headers $Headers
}
catch {
    Throw "Failed to fetch GitHub API data. Check the URL and token. Error: $_"
}

# 3. Extract Info
$Version = $ReleaseInfo.tag_name -replace "^v", ""
$Description = if ($RepoInfo.description) { $RepoInfo.description } else { "Description for $Repo" }
$Homepage = $RepoInfo.html_url
$License = if ($RepoInfo.license) { $RepoInfo.license.spdx_id } else { "Unknown" }
$ReleaseUrl = $ReleaseInfo.html_url

# 4. Find Asset
$Asset = Get-MatchingAsset -Assets $ReleaseInfo.assets

if (-not $Asset) {
    Throw "No suitable asset found in the latest release."
}

Write-Host "Selected asset: $($Asset.name)"
Write-Host "Download URL: $($Asset.browser_download_url)"

# 5. Download and Hash
$TempFile = Join-Path $env:TEMP $Asset.name
Write-Host "Downloading to $TempFile..."
Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $TempFile
$Hash = (Get-FileHash $TempFile -Algorithm SHA256).Hash

# 6. Inspect Archive (Optional - Bin Detection)
$Bin = $null
$ExtractDir = $null
$Shortcuts = @()

if ($Asset.name -match "\.(zip|7z)$") {
    try {
        Write-Host "Inspecting archive..."
        # Note: Expand-Archive only works for zip. 7z requires 7z.exe.
        # We'll assume zip for standard PowerShell, skip others.
        if ($Asset.name -match "\.zip$") {
            $Content = Open-Zip $TempFile
            # Simple heuristic: find .exe
            $Exes = $Content | Where-Object { $_.Name -match "\.exe$" }
            Write-Host "Found $($Exes.Count) EXEs in archive."

            if ($Exes.Count -eq 1) {
                $Bin = $Exes[0].Name
            }
            elseif ($Exes.Count -gt 1) {
                # 1. Try exact/regex match with Repo name
                $Match = $Exes | Where-Object { $_.Name -match "$Repo" } | Select-Object -First 1

                # 2. Try loose match (ignoring hyphens/underscores)
                if (-not $Match) {
                    $RepoClean = $Repo -replace "[-_]", ""
                    $Match = $Exes | Where-Object {
                        ($_.Name -replace "[-_]", "") -match $RepoClean
                    } | Select-Object -First 1
                }

                if ($Match) { $Bin = $Match.Name }
            }

            # Check for root folder
            $Roots = $Content | Where-Object { $_.FullName -match "^[^/]+/$" }
            # This is tricky with .NET ZipFile, let's skip complex extract_dir logic for now
            # and just check if all files are in a subdir matching the filename logic
            $PossibleRoot = $Asset.name -replace "\.zip$", ""
            # Logic omitted for brevity/stability, user can verify
        }
    }
    catch {
        Write-Warning "Failed to inspect archive: $_"
    }
}
elseif ($Asset.name -match "\.exe$") {
    # For exe installers (innosetup etc), bin is usually generated or extracted
    # If it's a portable exe, bin is the filename
    $Bin = $Asset.name
}

# Cleanup
Remove-Item $TempFile -Force

# 7. Construct JSON
$Manifest = [ordered]@{
    version      = $Version
    description  = $Description
    homepage     = $Homepage
    license      = $License
    architecture = @{
        "64bit" = [ordered]@{
            url  = $Asset.browser_download_url
            hash = $Hash
        }
    }
}

if ($Bin) { $Manifest["bin"] = $Bin }
if ($ExtractDir) { $Manifest["extract_dir"] = $ExtractDir }

if ($CreateShortcutBool -and $Bin) {
    $Manifest["shortcuts"] = @( , @($Bin, $Repo) )
}

$Manifest["checkver"] = "github"

# Autoupdate logic
$AutoUpdateUrl = $Asset.browser_download_url -replace $Version, "`$version"
$Manifest["autoupdate"] = @{
    architecture = @{
        "64bit" = @{
            url = $AutoUpdateUrl
        }
    }
}
if ($ExtractDir) {
    $Manifest["autoupdate"]["architecture"]["64bit"]["extract_dir"] = $ExtractDir -replace $Version, "`$version"
}

# 8. Save File
$FileName = "$Repo.json"
$FilePath = Join-Path "bucket" $FileName
$Manifest | ConvertTo-Json -Depth 10 | Set-Content $FilePath
Write-Host "Manifest saved to $FilePath"

# 9. Generate PR Body
$Report = @"
## Automatic App Manifest Generation

**Repository**: [$Owner/$Repo]($Homepage)
**Release**: [View Release Page]($ReleaseUrl)
**Version**: $Version
**License**: $License
**Description**: $Description

### Detection Status

| Field | Status | Value |
|-------|--------|-------|
| ``version`` | ✅ Detected | $Version |
| ``description`` | ✅ Detected | (See above) |
| ``homepage`` | ✅ Detected | $Homepage |
| ``license`` | ✅ Detected | $License |
| ``architecture.64bit`` | ✅ Detected | $($Asset.name) |
| ``hash`` | ✅ Calculated | $Hash |
| ``bin`` | $(if ($Bin) { "⚠️ Suggested" } else { "⭕ Missing" }) | $(if ($Bin) { "``$Bin`` (Please Verify)" } else { "Please fill manually" }) |
| ``shortcuts`` | $(if ($CreateShortcutBool -and $Bin) { "✅ Generated" } else { "⭕ Missing" }) | $(if ($CreateShortcutBool -and $Bin) { "Included" } else { "Please fill manually if needed" }) |
| ``persist`` | ⭕ Missing | Please fill manually if needed |
| ``checkver`` | ✅ Configured | ``github`` |
| ``autoupdate`` | ⚠️ Suggested | URL pattern generated |

### Action Required
1. Verify ``bin`` executable name.
2. Check if ``extract_dir`` is needed (nested folders in zip).
3. $(if ($CreateShortcutBool -and $Bin) { "Verify generated shortcuts." } else { "Add ``shortcuts`` if this is a GUI app." })
4. Add ``persist`` if the app creates config files in its directory.

"@

$Report | Set-Content $ReportPath

# Helper for Zip (using System.IO.Compression.FileSystem)
function Open-Zip {
    param($Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    return $Zip.Entries
}
