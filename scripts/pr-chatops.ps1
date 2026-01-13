# scripts/pr-chatops.ps1
param (
    [string]$Command,
    [string]$ArgsLine
)

$ErrorActionPreference = 'Stop'

function Get-ManifestPath {
    $files = git diff --name-only origin/main...HEAD | Where-Object { $_ -match '^bucket\\.*\.json$' -or $_ -match '^bucket/.*\.json$' }
    if (-not $files) {
        Write-Error "No manifest file found in the changes."
    }
    if ($files -is [array]) { return $files[0] }
    return $files
}

# Helper wrapper for jq
function Run-Jq {
    param(
        [string]$Path,
        [string]$Filter,
        [string]$Arg1 = $null,
        [string]$Arg2 = $null
    )

    $TempFile = "$Path.tmp"
    
    # Construct args list for jq
    $jqArgs = @()
    if ($Arg1) { $jqArgs += "--arg", "a1", $Arg1 }
    if ($Arg2) { $jqArgs += "--arg", "a2", $Arg2 }
    $jqArgs += $Filter
    $jqArgs += $Path

    Write-Host "Running jq filter: $Filter"
    # Execute jq using Start-Process or direct call depending on shell, but direct call is easier in pwsh
    # We pipeline input/output to avoid shell encoding issues if possible, but jq takes file arg nicely.
    
    # Run jq and capture output to temp file
    # Note: We use Invoke-Expression or & to run it.
    # To avoid quoting hell, we pass arguments carefully.
    
    $proc = Start-Process -FilePath "jq" -ArgumentList ($jqArgs) -NoNewWindow -PassThru -RedirectStandardOutput $TempFile
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
        Throw "jq execution failed."
    }

    Move-Item $TempFile $Path -Force
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
            if ($parsedArgs.Count -eq 1) {
                # .bin = "value"
                Run-Jq -Path $manifestPath -Filter '.bin = $a1' -Arg1 $parsedArgs[0]
                Write-Host "Set bin to: $($parsedArgs[0])"
            } elseif ($parsedArgs.Count -eq 2) {
                # .bin = [["exe", "alias"]]
                Run-Jq -Path $manifestPath -Filter '.bin = [[$a1, $a2]]' -Arg1 $parsedArgs[0] -Arg2 $parsedArgs[1]
                Write-Host "Set bin to alias: $($parsedArgs[0]) -> $($parsedArgs[1])"
            } else {
                Write-Error "Usage: /set-bin <exe> [alias]"
            }
        }
        "/set-shortcut" {
            if ($parsedArgs.Count -lt 2) { Write-Error "Usage: /set-shortcut <target> <name>" }
            # .shortcuts = [["exe", "name"]]
            Run-Jq -Path $manifestPath -Filter '.shortcuts = [[$a1, $a2]]' -Arg1 $parsedArgs[0] -Arg2 $parsedArgs[1]
            Write-Host "Set shortcut: $($parsedArgs[0]) -> $($parsedArgs[1])"
        }
        "/set-persist" {
             if ($parsedArgs.Count -eq 1) {
                # .persist = "value"
                Run-Jq -Path $manifestPath -Filter '.persist = $a1' -Arg1 $parsedArgs[0]
                Write-Host "Set persist to: $($parsedArgs[0])"
            } elseif ($parsedArgs.Count -eq 2) {
                # .persist = [["data", "alias"]]
                Run-Jq -Path $manifestPath -Filter '.persist = [[$a1, $a2]]' -Arg1 $parsedArgs[0] -Arg2 $parsedArgs[1]
                Write-Host "Set persist to alias: $($parsedArgs[0]) -> $($parsedArgs[1])"
            } else {
                Write-Error "Usage: /set-persist <file> [alias]"
            }
        }
        "/set-key" {
            if ($parsedArgs.Count -lt 2) { Write-Error "Usage: /set-key <key> <value>" }
            # Dynamic key update: .[$key] = $value
            # Note: We need to pass key as a separate arg to be safe
            # But Run-Jq helper only takes 2 args. Let's customize for this case.
            
            $key = $parsedArgs[0]
            $val = $parsedArgs[1]
            
            # Use specific filter for this
            $filter = ".[""$key""] = `$a1" 
            # Note: PowerShell interpolation for $key, but $a1 is jq variable
            
            Run-Jq -Path $manifestPath -Filter ".[`"$key`"] = `$a1" -Arg1 $val
            Write-Host "Set $key = $val"
        }
        default {
            Write-Error "Unknown command: $Command"
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
