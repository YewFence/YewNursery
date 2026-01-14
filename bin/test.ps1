#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'BuildHelpers'; ModuleVersion = '2.0.1' }
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

$pesterConfig = New-PesterConfiguration -Hashtable @{
    Run    = @{
        Path     = "$PSScriptRoot/.."
        PassThru = $true
    }
    Output = @{
        Verbosity = 'Detailed'
    }
}

# In CI, only validate changed JSON manifests under bucket/.
function global:Get-GitChangedFile {
    [CmdletBinding(DefaultParameterSetName = "All")]
    param(
        [validateScript({ Test-Path $_ -PathType Container })]
        [Parameter(ParameterSetName = "All")]
        [Parameter(ParameterSetName = "Commit")]
        [Parameter(ParameterSetName = "Range")]
        [Parameter(ParameterSetName = "RangeLeft")]
        [Parameter(ParameterSetName = "RangeRight")]
        [Parameter(ParameterSetName = "RawRevision")]
        $Path = $PWD.Path,

        [Parameter(Mandatory, ParameterSetName = "Commit", Position = 0)]
        [string]$Commit,

        [Parameter(Mandatory, ParameterSetName = "Range")]
        [Parameter(Mandatory, ParameterSetName = "RangeLeft")]
        [string]$LeftRevision,

        [Parameter(ParameterSetName = "Range")]
        [Parameter(ParameterSetName = "RangeLeft")]
        [Parameter(ParameterSetName = "RangeRight")]
        [ValidateSet("..", "...")]
        [string]$RangeNotation = "...",

        [Parameter(Mandatory, ParameterSetName = "Range")]
        [Parameter(Mandatory, ParameterSetName = "RangeRight")]
        [string]$RightRevision,

        [ValidatePattern("^[ACDMRTUXBacdmrtuxb*]+$")]
        [string]$DiffFilter,

        [Parameter(ParameterSetName = "RawRevision")]
        [string]$RawRevisionString,

        [string[]]$Include,

        [string[]]$Exclude,

        [switch]$Resolve
    )

    $results = BuildHelpers\Get-GitChangedFile @PSBoundParameters
    if (-not $results) {
        return $results
    }

    if ($env:CI -eq 'true') {
        return $results | Where-Object { $_ -match '[\\/]+bucket[\\/].+\.json$' }
    }

    return $results
}

$result = Invoke-Pester -Configuration $pesterConfig
exit $result.FailedCount
