$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$allErrors = [System.Collections.Generic.List[string]]::new()

foreach ($directory in @('installer', 'tools')) {
    Get-ChildItem -LiteralPath (Join-Path $projectDirectory $directory) -Filter '*.ps1' -Recurse -File | ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
        foreach ($error in @($parseErrors)) {
            $allErrors.Add("$($_.FullName):$($error.Extent.StartLineNumber) $($error.Message)")
        }
    }
}

if ($allErrors.Count -gt 0) {
    $allErrors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Syntaxe PowerShell valide.'

