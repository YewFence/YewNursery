# scripts/pr-chatops.ps1
param (
    [string]$Command,
    [string]$ArgsLine,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/utils.ps1"

# Resolve Manifest Path if not provided
if (-not $ManifestPath) {
    if ($env:TARGET_MANIFEST) {
        $ManifestPath = $env:TARGET_MANIFEST
    } else {
        try {
            $ManifestPath = Get-ChangedManifestPath
        } catch {
            Write-Error "Could not determine manifest path: $_"
            exit 1
        }
    }
}

if (-not (Test-Path $ManifestPath)) {
    Write-Error "Manifest file not found: $ManifestPath"
    exit 1
}

Write-Host "Target manifest: $ManifestPath"

# Parse Arguments using PowerShell's tokenizer
function Parse-Args {
    param($Line)
    $tokens = [System.Management.Automation.PSParser]::Tokenize($Line, [ref]$null)
    $argsList = @()
    foreach ($t in $tokens) {
        # Allow Command, String, CommandArgument types
        if ($t.Type -in @('String', 'CommandArgument', 'Command')) {
            if (-not [string]::IsNullOrWhiteSpace($t.Content)) {
                $argsList += $t.Content
            }
        }
    }
    return $argsList
}

# Function to load, modify and save JSON
function Update-Manifest {
    param([scriptblock]$Action)
    
    $json = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    
    # Invoke the modification logic
    & $Action $json
    
    # Save back to file
    # We rely on 'formatjson' script to fix indentation/sorting later.
    # Depth 99 ensures deep structures (like bin arrays) aren't truncated.
    $json | ConvertTo-Json -Depth 99 | Set-Content $ManifestPath -Encoding utf8
}

try {
    $parsedArgs = @(Parse-Args $ArgsLine)
    Write-Host "Processing command: $Command with args: $($parsedArgs -join ', ')"

    switch ($Command) {
        "/set-bin" {
            if ($parsedArgs.Count -eq 1) {
                # .bin = "value"
                Update-Manifest { param($j) $j.bin = $parsedArgs[0] }
                Write-Host "Set bin to: $($parsedArgs[0])"
            } elseif ($parsedArgs.Count -eq 2) {
                # .bin = [["exe", "alias"]]
                # Note: We create nested array structure
                Update-Manifest { param($j) $j.bin = @( @($parsedArgs[0], $parsedArgs[1]) ) }
                Write-Host "Set bin to alias: $($parsedArgs[0]) -> $($parsedArgs[1])"
            } else {
                Throw "Usage: /set-bin <exe> [alias]"
            }
        }
        "/set-shortcut" {
            $target = $null
            $shortcutName = $null

            if ($parsedArgs.Count -eq 1) {
                # Usage: /set-shortcut <name> (Auto-detect target)
                $shortcutName = $parsedArgs[0]
                
                # We need to read the file first to auto-detect
                $currentJson = Get-Content $ManifestPath -Raw | ConvertFrom-Json
                
                if ($currentJson.bin) {
                    if ($currentJson.bin -is [string]) {
                        $target = $currentJson.bin
                    } elseif ($currentJson.bin -is [array] -and $currentJson.bin.Count -gt 0) {
                        $first = $currentJson.bin[0]
                        if ($first -is [string]) {
                            $target = $first
                        } elseif ($first -is [array] -and $first.Count -gt 0) {
                            $target = $first[0]
                        }
                    }
                }

                if (-not $target) {
                    Throw "Could not automatically detect 'bin' in manifest. Please specify target: /set-shortcut <target> <name>"
                }
                Write-Host "Auto-detected shortcut target: $target"

            } elseif ($parsedArgs.Count -eq 2) {
                $target = $parsedArgs[0]
                $shortcutName = $parsedArgs[1]
            } else {
                Throw "Usage: /set-shortcut <name> (auto-bin) OR /set-shortcut <target> <name>"
            }

            # .shortcuts = [["exe", "name"]]
            Update-Manifest { param($j) $j.shortcuts = @( @($target, $shortcutName) ) }
            Write-Host "Set shortcut: $target -> $shortcutName"
        }
        "/set-persist" {
             if ($parsedArgs.Count -eq 1) {
                # .persist = "value"
                Update-Manifest { param($j) $j.persist = $parsedArgs[0] }
                Write-Host "Set persist to: $($parsedArgs[0])"
            } elseif ($parsedArgs.Count -eq 2) {
                # .persist = [["data", "alias"]]
                Update-Manifest { param($j) $j.persist = @( @($parsedArgs[0], $parsedArgs[1]) ) }
                Write-Host "Set persist to alias: $($parsedArgs[0]) -> $($parsedArgs[1])"
            } else {
                Throw "Usage: /set-persist <file> [alias]"
            }
        }
        "/set-key" {
            if ($parsedArgs.Count -lt 2) { Throw "Usage: /set-key <key> <value>" }
            $key = $parsedArgs[0]
            $val = $parsedArgs[1]

            if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                Throw "Invalid key format. Keys must be alphanumeric with underscores."
            }

            Update-Manifest { 
                param($j) 
                if ($j.PSObject.Properties.Match($key).Count) {
                    $j.$key = $val
                } else {
                    $j | Add-Member -NotePropertyName $key -NotePropertyValue $val
                }
            }
            Write-Host "Set $key = $val"
        }
        "/list-config" {
            if ($parsedArgs.Count -gt 0) { Throw "Usage: /list-config" }
            Write-Host "Listing current config for: $ManifestPath"
            $content = Get-Content -Raw $ManifestPath
            try {
                $json = $content | ConvertFrom-Json
                Write-Host ($json | ConvertTo-Json -Depth 10)
            } catch {
                Write-Host $content
            }
        }
        default {
            Throw "Unknown command: $Command"
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
