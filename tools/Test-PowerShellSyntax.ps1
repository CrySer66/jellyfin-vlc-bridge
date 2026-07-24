$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$allErrors = [System.Collections.Generic.List[string]]::new()
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)

foreach ($directory in @('installer', 'tools')) {
    Get-ChildItem -LiteralPath (Join-Path $projectDirectory $directory) -Filter '*.ps1' -Recurse -File | ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        try {
            $content = [IO.File]::ReadAllText($_.FullName, $utf8)
            [void][System.Management.Automation.Language.Parser]::ParseInput($content, $_.FullName, [ref]$tokens, [ref]$parseErrors)
        } catch {
            $allErrors.Add("$($_.FullName): encodage UTF-8 invalide ($($_.Exception.Message))")
            return
        }
        foreach ($parseError in @($parseErrors)) {
            $allErrors.Add("$($_.FullName):$($parseError.Extent.StartLineNumber) $($parseError.Message)")
        }
    }
}

if ($allErrors.Count -gt 0) {
    $allErrors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Syntaxe PowerShell valide.'
