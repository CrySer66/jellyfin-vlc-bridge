param(
    [string]$InputDirectory = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($InputDirectory)) {
    $InputDirectory = Join-Path $projectDirectory 'browser-extension\icons'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectDirectory 'assets\JellyfinVlcBridge.ico'
}

$images = foreach ($size in @(16, 32, 48, 128)) {
    $path = Join-Path $InputDirectory "icon$size.png"
    if (-not (Test-Path -LiteralPath $path)) { throw "Icône source manquante : $path" }
    [PSCustomObject]@{ Size = $size; Bytes = [IO.File]::ReadAllBytes($path) }
}

$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write)
$writer = New-Object IO.BinaryWriter($stream)
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$images.Count)

    $offset = 6 + (16 * $images.Count)
    foreach ($image in $images) {
        $writer.Write([byte]$image.Size)
        $writer.Write([byte]$image.Size)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$image.Bytes.Length)
        $writer.Write([UInt32]$offset)
        $offset += $image.Bytes.Length
    }
    foreach ($image in $images) { $writer.Write($image.Bytes) }
} finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output $OutputPath
