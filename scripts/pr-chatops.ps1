# scripts/pr-chatops.ps1
param (
    [string]$Command,
    [string]$ArgsLine,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

# Resolve Manifest Path if not provided
if (-not $ManifestPath) {
    if ($env:TARGET_MANIFEST) {
        $ManifestPath = $env:TARGET_MANIFEST
    }
    else {
        Write-Error "ManifestPath argument or TARGET_MANIFEST environment variable is required."
        exit 1
    }
}

if (-not (Test-Path $ManifestPath)) {
    Write-Error "Manifest file not found: $ManifestPath"
    exit 1
}

Write-Host "Target manifest: $ManifestPath"

# Parse Arguments using PowerShell's tokenizer with quote support
function Parse-Args {
    param($Line)
    
    if ([string]::IsNullOrWhiteSpace($Line)) {
        return @()
    }
    
    $args = @()
    $current = ''
    $inQuote = $false
    $quoteChar = ''
    
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $char = $Line[$i]
        
        if ($inQuote) {
            if ($char -eq $quoteChar) {
                # End quote
                $inQuote = $false
            }
            else {
                $current += $char
            }
        }
        else {
            if ($char -eq '"' -or $char -eq "'") {
                # Start quote
                $inQuote = $true
                $quoteChar = $char
            }
            elseif ($char -match '\s') {
                # Whitespace outside quotes
                if ($current) {
                    $args += $current
                    $current = ''
                }
            }
            else {
                $current += $char
            }
        }
    }
    
    # Add last token
    if ($current) {
        $args += $current
    }
    
    if ($inQuote) {
        throw "Unclosed quote: expected closing $quoteChar"
    }
    
    return $args
}

# Helper to append or set property
function Add-OrAppend-Property {
    param($j, $prop, $val)
    
    if ($j.PSObject.Properties.Match($prop).Count) {
        $current = $j.$prop
        
        # If current is explicitly null, treat as new
        if ($null -eq $current) {
            $j.$prop = $val
            return
        }

        # Normalize current to array
        $currentArray = @()
        if ($current -is [array]) {
            $currentArray = $current
        }
        else {
            $currentArray = @($current)
        }
        
        # Append new value. 
        # We use @( , $val ) to ensure $val is treated as a single item 
        # even if it is an array (like ["exe", "alias"]).
        $j.$prop = $currentArray + @( , $val )
    }
    else {
        $j | Add-Member -NotePropertyName $prop -NotePropertyValue $val
    }
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
                Update-Manifest { param($j) Add-OrAppend-Property $j "bin" $parsedArgs[0] }
                Write-Host "Added bin: $($parsedArgs[0])"
            }
            elseif ($parsedArgs.Count -eq 2) {
                # .bin = [["exe", "alias"]]
                $val = @($parsedArgs[0], $parsedArgs[1])
                Update-Manifest { param($j) Add-OrAppend-Property $j "bin" $val }
                Write-Host "Added bin alias: $($parsedArgs[0]) -> $($parsedArgs[1])"
            }
            else {
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
                    }
                    elseif ($currentJson.bin -is [array] -and $currentJson.bin.Count -gt 0) {
                        $first = $currentJson.bin[0]
                        if ($first -is [string]) {
                            $target = $first
                        }
                        elseif ($first -is [array] -and $first.Count -gt 0) {
                            $target = $first[0]
                        }
                    }
                }

                if (-not $target) {
                    Throw "Could not automatically detect 'bin' in manifest. Please specify target: /set-shortcut <target> <name>"
                }
                Write-Host "Auto-detected shortcut target: $target"

            }
            elseif ($parsedArgs.Count -eq 2) {
                $target = $parsedArgs[0]
                $shortcutName = $parsedArgs[1]
            }
            else {
                Throw "Usage: /set-shortcut <name> (auto-bin) OR /set-shortcut <target> <name>"
            }

            # .shortcuts = [["exe", "name"]]
            $val = @($target, $shortcutName)
            Update-Manifest { param($j) Add-OrAppend-Property $j "shortcuts" $val }
            Write-Host "Added shortcut: $target -> $shortcutName"
        }
        "/set-persist" {
            if ($parsedArgs.Count -eq 1) {
                # .persist = "value"
                Update-Manifest { param($j) Add-OrAppend-Property $j "persist" $parsedArgs[0] }
                Write-Host "Added persist: $($parsedArgs[0])"
            }
            elseif ($parsedArgs.Count -eq 2) {
                # .persist = [["data", "alias"]]
                $val = @($parsedArgs[0], $parsedArgs[1])
                Update-Manifest { param($j) Add-OrAppend-Property $j "persist" $val }
                Write-Host "Added persist alias: $($parsedArgs[0]) -> $($parsedArgs[1])"
            }
            else {
                Throw "Usage: /set-persist <file> [alias]"
            }
        }
        "/set-key" {
            if ($parsedArgs.Count -lt 2) { Throw "Usage: /set-key <key> <value>" }
            $key = $parsedArgs[0]
            # Join all remaining args to support multi-word values
            $val = $parsedArgs[1..($parsedArgs.Count - 1)] -join ' '

            if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                Throw "Invalid key format. Keys must be alphanumeric with underscores."
            }

            # Try to parse as JSON for objects/arrays, otherwise keep as string
            if ($val -match '^[\[\{]') {
                try {
                    $val = $val | ConvertFrom-Json
                    Write-Host "Parsed value as JSON: $($val | ConvertTo-Json -Compress)"
                }
                catch {
                    Write-Host "Keeping value as string (JSON parse failed): $val"
                }
            }

            # /set-key behavior remains "overwrite" as it targets specific keys
            Update-Manifest { 
                param($j) 
                if ($j.PSObject.Properties.Match($key).Count) {
                    $j.$key = $val
                }
                else {
                    $j | Add-Member -NotePropertyName $key -NotePropertyValue $val
                }
            }
            Write-Host "Set $key = $val"
        }
        "/clean" {
            if ($parsedArgs.Count -ne 1) { Throw "Usage: /clean <field>" }
            $field = $parsedArgs[0]
            Update-Manifest { 
                param($j) 
                if ($j.PSObject.Properties.Match($field).Count) {
                    $j.PSObject.Properties.Remove($field)
                }
            }
            Write-Host "Cleaned field: $field"
        }
        "/list-config" {
            if ($parsedArgs.Count -gt 0) { Throw "Usage: /list-config" }
            Write-Host "Listing current config for: $ManifestPath"
            $content = Get-Content -Raw $ManifestPath
            try {
                $json = $content | ConvertFrom-Json
                Write-Host ($json | ConvertTo-Json -Depth 10)
            }
            catch {
                Write-Host $content
            }
        }
        default {
            Throw "Unknown command: $Command"
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
