# scripts/pr-chatops.ps1
param (
    [string]$Command,
    [string]$ArgsLine
)

$ErrorActionPreference = 'Stop'

function Get-ManifestPath {
    $files = git diff --name-only --diff-filter=ACM origin/main...HEAD -- bucket | Where-Object { $_ -match '^bucket[\\/].+\.json$' }
    if (-not $files) {
        Write-Error "No manifest file found in the changes."
    }
    if ($files -is [array] -and $files.Count -gt 1) {
        Write-Error "Multiple manifest files found in the changes. Please modify one manifest per PR."
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

    $StdErrFile = "$TempFile.err"
    $proc = Start-Process -FilePath "jq" -ArgumentList ($jqArgs) -NoNewWindow -PassThru -RedirectStandardOutput $TempFile -RedirectStandardError $StdErrFile
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        $errMsg = if (Test-Path $StdErrFile) { Get-Content -Raw $StdErrFile } else { "Unknown error" }
        Remove-Item $StdErrFile -Force -ErrorAction SilentlyContinue
        Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
        Throw "jq execution failed: $errMsg"
    }

    Remove-Item $StdErrFile -Force -ErrorAction SilentlyContinue
    Move-Item $TempFile $Path -Force
}

# Parse Arguments using PowerShell's tokenizer to handle quotes correctly
function Parse-Args {
    param($Line)
    $tokens = [System.Management.Automation.PSParser]::Tokenize($Line, [ref]$null)
    $argsList = @()
    foreach ($t in $tokens) {
        if ($t.Type -in @('String', 'CommandArgument')) {
            if (-not [string]::IsNullOrWhiteSpace($t.Content)) {
                $argsList += $t.Content
            }
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
            $target = $null
            $shortcutName = $null

            if ($parsedArgs.Count -eq 1) {
                # Usage: /set-shortcut <name> (Auto-detect target)
                $shortcutName = $parsedArgs[0]

                # Read manifest to find bin
                try {
                    $json = Get-Content $manifestPath -Raw | ConvertFrom-Json
                    if ($json.bin) {
                        if ($json.bin -is [string]) {
                            $target = $json.bin
                        } elseif ($json.bin -is [array] -and $json.bin.Count -gt 0) {
                            $first = $json.bin[0]
                            if ($first -is [string]) {
                                $target = $first
                            } elseif ($first -is [array] -and $first.Count -gt 0) {
                                $target = $first[0]
                            }
                        }
                    }
                } catch {
                    Write-Error "Failed to parse manifest JSON to infer bin path."
                }

                if (-not $target) {
                    Write-Error "Could not automatically detect 'bin' in manifest. Please specify target: /set-shortcut <target> <name>"
                }
                Write-Host "Auto-detected shortcut target: $target"

            } elseif ($parsedArgs.Count -eq 2) {
                # Usage: /set-shortcut <target> <name>
                $target = $parsedArgs[0]
                $shortcutName = $parsedArgs[1]
            } else {
                Write-Error "Usage: /set-shortcut <name> (auto-bin) OR /set-shortcut <target> <name>"
            }

            # .shortcuts = [["exe", "name"]]
            Run-Jq -Path $manifestPath -Filter '.shortcuts = [[$a1, $a2]]' -Arg1 $target -Arg2 $shortcutName
            Write-Host "Set shortcut: $target -> $shortcutName"
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

            if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                Write-Error "Invalid key format. Keys must be alphanumeric with underscores."
            }

            Run-Jq -Path $manifestPath -Filter '.[$a1] = $a2' -Arg1 $key -Arg2 $val
            Write-Host "Set $key = $val"
        }
        "/list-config" {
            if ($parsedArgs.Count -gt 0) { Write-Error "Usage: /list-config" }
            Write-Host "Listing current config for: $manifestPath"
            $content = Get-Content -Raw $manifestPath
            try {
                $json = $content | ConvertFrom-Json
                Write-Host ($json | ConvertTo-Json -Depth 10)
            } catch {
                Write-Host $content
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
