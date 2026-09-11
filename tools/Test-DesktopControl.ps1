param()

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The .NET Framework C# compiler was not found.'
}
$workDirectory = [IO.Path]::GetFullPath((Join-Path $projectDirectory 'work'))
$testDirectory = [IO.Path]::GetFullPath((Join-Path $workDirectory ('desktop-tests-' + [Guid]::NewGuid().ToString('N'))))
if (-not $testDirectory.StartsWith($workDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The test directory must remain inside the project work directory.'
}
New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
try {
    $executable = Join-Path $testDirectory 'DesktopControlTests.exe'
    & $compiler /nologo /target:exe /langversion:5 /reference:System.Web.Extensions.dll "/out:$executable" `
        (Join-Path $projectDirectory 'installer\ControlCenterServices.cs') `
        (Join-Path $projectDirectory 'tests\DesktopControlTests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Desktop service tests did not compile.' }
    Copy-Item -LiteralPath $executable -Destination (Join-Path $testDirectory 'jellyfin-vlc-bridge.exe')
    & $executable $testDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Desktop service tests failed.' }
}
finally {
    $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
    if ($resolvedTestDirectory.StartsWith($workDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTestDirectory)) {
        Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
    }
}
