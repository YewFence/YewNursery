# scripts/pr-chatops.ps1
param (
    [string]$Command,
    [string]$ArgsLine
)

$ErrorActionPreference = 'Stop'

function Get-ManifestPath {
    # Find the modified .json file in bucket/
    # In a PR context, we might rely on git diff or just look for the file mentioned in the PR or just find the single changed json file.
    # For simplicity, assuming the PR mainly touches one app manifest or we pick the first one found in bucket/ that is modified.
    # Actually, relying on git diff --name-only origin/main...HEAD is safer.

    $files = git diff --name-only origin/main...HEAD | Where-Object { $_ -match '^bucket\\.*\.json$' -or $_ -match '^bucket/.*\.json$' }
    if (-not $files) {
        Write-Error "No manifest file found in the changes."
    }
    # Return the first one
    if ($files -is [array]) { return $files[0] }
    return $files
}

function Update-Json {
    param($Path, $ScriptBlock)
    $json = Get-Content $Path -Raw | ConvertFrom-Json
    & $ScriptBlock $json

    # We rely on formatjson.ps1 later to fix indentation, so just dump it here
    $json | ConvertTo-Json -Depth 100 | Set-Content $Path
}

# Parse Arguments using PowerShell's tokenizer to handle quotes correctly
function Parse-Args {
    param($Line)
    $tokens = [System.Management.Automation.PSParser]::Tokenize($Line, [ref]$null)
    $argsList = @()
    foreach ($t in $tokens) {
        if ($t.Type -eq 'String') {
            $argsList += $t.Content
        }
    }
    return $argsList
}

try {
    Write-Host "Processing command: $Command with args: $ArgsLine"

    $manifestPath = Get-ManifestPath
    Write-Host "Target manifest: $manifestPath"

    $parsedArgs = Parse-Args $ArgsLine

    switch ($Command) {
        "/set-bin" {
            Update-Json $manifestPath {
                param($j)
                if ($parsedArgs.Count -eq 1) {
                    $j.bin = $parsedArgs[0]
                    Write-Host "Set bin to: $($parsedArgs[0])"
                } elseif ($parsedArgs.Count -eq 2) {
                    $j.bin = @( @($parsedArgs[0], $parsedArgs[1]) )
                    Write-Host "Set bin to alias: $($parsedArgs[0]) -> $($parsedArgs[1])"
                } else {
                    Write-Error "Usage: /set-bin <exe> [alias]"
                }
            }
        }
        "/set-shortcut" {
            Update-Json $manifestPath {
                param($j)
                if ($parsedArgs.Count -lt 2) { Write-Error "Usage: /set-shortcut <target> <name>" }

                $j.shortcuts = @( @($parsedArgs[0], $parsedArgs[1]) )
                Write-Host "Set shortcut: $($parsedArgs[0]) -> $($parsedArgs[1])"
            }
        }
        "/set-persist" {
            Update-Json $manifestPath {
                param($j)
                if ($parsedArgs.Count -eq 1) {
                    $j.persist = $parsedArgs[0]
                    Write-Host "Set persist to: $($parsedArgs[0])"
                } elseif ($parsedArgs.Count -eq 2) {
                    $j.persist = @( @($parsedArgs[0], $parsedArgs[1]) )
                    Write-Host "Set persist to alias: $($parsedArgs[0]) -> $($parsedArgs[1])"
                } else {
                    Write-Error "Usage: /set-persist <file> [alias]"
                }
            }
        }
        "/set-key" {
            Update-Json $manifestPath {
                param($j)
                if ($parsedArgs.Count -lt 2) { Write-Error "Usage: /set-key <key> <value>" }
                $key = $parsedArgs[0]
                $val = $parsedArgs[1]
                $j.$key = $val
                Write-Host "Set $key = $val"
            }
        }
        default {
            Write-Error "Unknown command: $Command"
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
