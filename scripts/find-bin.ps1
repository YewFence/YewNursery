param (
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string]$AppName = ""
)

$ErrorActionPreference = "Stop"

# --- Constants ---
$ExecExtensions = @(".exe", ".bat", ".cmd", ".ps1")
$Blacklist = @("uninstall", "unins000", "setup", "install", "update", "config", "crashreporter", "uninst")
$BinDirs = @("bin", "dist")

# --- Helpers ---

function Get-Tree {
    param($Paths, $MaxDepth=3)

    # Build a simple nested hashtable structure
    $root = @{}

    foreach ($path in $Paths) {
        $parts = $path -split '[/\\]'
        $current = $root

        # Only go up to MaxDepth
        $limit = [Math]::Min($parts.Count, $MaxDepth)

        for ($i = 0; $i -lt $limit; $i++) {
            $part = $parts[$i]
            if (-not $current.ContainsKey($part)) {
                $current[$part] = @{}
            }
            $current = $current[$part]
        }
    }

    # Render tree
    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine("📂 (root)")

    Render-Node -Node $root -Prefix "" -StringBuilder $sb -Last $true

    return $sb.ToString()
}

function Render-Node {
    param($Node, $Prefix, $StringBuilder, $Last)

    $keys = $Node.Keys | Sort-Object
    $count = $keys.Count
    $i = 0

    foreach ($key in $keys) {
        $i++
        $isLast = ($i -eq $count)

        $marker = if ($isLast) { "└── " } else { "├── " }
        $childPrefix = if ($isLast) { "    " } else { "│   " }

        # Check if it looks like a file (has extension) or dir
        # This is a heuristic since we only have paths
        $icon = if ($key -match "\.") { "📄" } else { "📂" }

        $StringBuilder.AppendLine("$Prefix$marker$icon $key")

        if ($Node[$key].Count -gt 0) {
            Render-Node -Node $Node[$key] -Prefix "$Prefix$childPrefix" -StringBuilder $StringBuilder -Last $isLast
        }
    }
}

function Normalize-Name {
    param($Name)
    if (-not $Name) { return "" }
    # Remove version numbers, arch, platform
    $n = $Name -replace "[-_.]?(v?\d+\.\d+(\.\d+)?).*", ""
    $n = $n -replace "[-_](windows|win|win64|x64|x86_64|portable|amd64).*", ""
    return $n
}

# --- Main Logic ---

# 1. Inspect Archive
try {
    # -slt provides: Path = ... \n Folder = ... \n ...
    $output = 7z l -slt $FilePath
} catch {
    Write-Warning "Failed to inspect archive with 7zip."
    return $null
}

$fileList = @()
$rawPaths = @() # For tree generation

$currentPath = ""
$isDir = $false
$currentAttrib = ""

foreach ($line in $output) {
    if ($line -match '^Path = (.*)') {
        $currentPath = $Matches[1]
    } elseif ($line -match '^Folder = \+') {
        $isDir = $true
    } elseif ($line -eq "") {
        # Block finished
        if ($currentPath) {
            if (-not $isDir) {
                # Check extension
                $ext = [System.IO.Path]::GetExtension($currentPath).ToLower()

                # For the tree, we want to show executable files AND directory structure
                # But we can't easily distinguish empty intermediate dirs from the 7z output style if we just list files
                # However, for the user request, they want to see "structure"
                # We will collect ALL executables for candidate analysis
                # And collecting paths for the tree.
                # To keep tree clean, maybe we only add Executables to the tree?
                # The user asked: "list all bat,cmd,ps1,exe inside a 3-level folder structure"

                if ($ExecExtensions -contains $ext) {
                    $fileList += $currentPath
                    $rawPaths += $currentPath
                }
            }
        }
        # Reset
        $currentPath = ""
        $isDir = $false
    }
}

# If no executables found, try to be helpful and show at least something in tree?
# Or just return empty
if ($fileList.Count -eq 0) {
    return @{
        Recommended = $null
        Candidates = @()
        Tree = "No executable files found."
        ExtractDir = $null
    }
}

# 2. Analyze Structure for ExtractDir (Common Prefix)
$extractDir = $null
if ($fileList.Count -gt 0) {
    # We need to look at ALL files for ExtractDir logic, not just exes,
    # but strictly speaking Scoop handles this based on top-level content.
    # For simplicity, let's assume if all EXEs are in a subdir, likely everything is.
    # A robust check needs all files, but let's stick to the list we have or re-parse everything?
    # Re-parsing is slow. Let's approximate from the EXE paths.

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

# 3. Score Candidates
$candidates = @()
$normalizedAppName = Normalize-Name -Name $AppName

foreach ($path in $fileList) {
    $score = 0
    $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    $dir = [System.IO.Path]::GetDirectoryName($path)

    # Rule 1: Blacklist (Strong reject)
    $isBlacklisted = $false
    foreach ($bad in $Blacklist) {
        if ($name -match $bad) {
            $score -= 100
            $isBlacklisted = $true
            break
        }
    }

    # Rule 2: Extension Priority
    if ($ext -eq ".exe") { $score += 10 }
    elseif ($ext -eq ".cmd" -or $ext -eq ".bat") { $score += 5 }

    # Rule 3: Directory Preference
    if ([string]::IsNullOrWhiteSpace($dir) -or $dir -eq ".") {
        $score += 10 # Root is good
    } else {
        # Check for bin/dist
        foreach ($goodDir in $BinDirs) {
            if ($dir -match $goodDir) { $score += 5 }
        }
    }

    # Rule 4: Name Match (The most important)
    if ($normalizedAppName) {
        if ($name -eq $normalizedAppName) {
            $score += 50 # Jackpot
        } elseif ($name -match "^$normalizedAppName" -or $name -match "$normalizedAppName$") {
            $score += 20 # Partial match
        } elseif ($name -match $normalizedAppName) {
            $score += 10 # Contains
        }
    }

    # Create object
    $candidates += [PSCustomObject]@{
        Path = $path
        Score = $score
        IsBlacklisted = $isBlacklisted
    }
}

# Sort candidates by score descending
$sorted = $candidates | Where-Object { -not $_.IsBlacklisted } | Sort-Object Score -Descending

$recommended = if ($sorted.Count -gt 0) { $sorted[0].Path } else { $null }

# 4. Generate Tree
$tree = Get-Tree -Paths $rawPaths

return @{
    Recommended = $recommended
    Candidates = $sorted.Path
    Tree = $tree
    ExtractDir = $extractDir
}
