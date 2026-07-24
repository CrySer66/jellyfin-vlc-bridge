param(
    [string]$Version = '1.8.0'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectDirectory = Split-Path -Parent $PSScriptRoot
$extensionDirectory = Join-Path $projectDirectory 'browser-extension'
$iconsDirectory = Join-Path $extensionDirectory 'icons'
$outputsDirectory = Join-Path $projectDirectory 'outputs'
New-Item -ItemType Directory -Path $iconsDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $outputsDirectory -Force | Out-Null

function New-RoundedRectangle([float]$x, [float]$y, [float]$width, [float]$height, [float]$radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2
    $path.AddArc($x, $y, $diameter, $diameter, 180, 90)
    $path.AddArc($x + $width - $diameter, $y, $diameter, $diameter, 270, 90)
    $path.AddArc($x + $width - $diameter, $y + $height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($x, $y + $height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-BridgeIcon([int]$size, [string]$destination) {
    $scale = 4
    $canvasSize = $size * $scale
    $bitmap = New-Object System.Drawing.Bitmap($canvasSize, $canvasSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $background = New-RoundedRectangle 0 0 $canvasSize $canvasSize ($canvasSize * 0.22)
        $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            ([System.Drawing.RectangleF]::new(0, 0, $canvasSize, $canvasSize)),
            [System.Drawing.ColorTranslator]::FromHtml('#00A4DC'),
            [System.Drawing.ColorTranslator]::FromHtml('#075985'),
            45)
        try { $graphics.FillPath($gradient, $background) } finally { $gradient.Dispose(); $background.Dispose() }

        $orange = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#F28C28'))
        $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        try {
            $cone = [System.Drawing.PointF[]]@(
                ([System.Drawing.PointF]::new($canvasSize * .50, $canvasSize * .14)),
                ([System.Drawing.PointF]::new($canvasSize * .25, $canvasSize * .76)),
                ([System.Drawing.PointF]::new($canvasSize * .75, $canvasSize * .76)))
            $graphics.FillPolygon($orange, $cone)

            $stripeOne = [System.Drawing.PointF[]]@(
                ([System.Drawing.PointF]::new($canvasSize * .40, $canvasSize * .39)),
                ([System.Drawing.PointF]::new($canvasSize * .60, $canvasSize * .39)),
                ([System.Drawing.PointF]::new($canvasSize * .64, $canvasSize * .49)),
                ([System.Drawing.PointF]::new($canvasSize * .36, $canvasSize * .49)))
            $stripeTwo = [System.Drawing.PointF[]]@(
                ([System.Drawing.PointF]::new($canvasSize * .31, $canvasSize * .62)),
                ([System.Drawing.PointF]::new($canvasSize * .69, $canvasSize * .62)),
                ([System.Drawing.PointF]::new($canvasSize * .73, $canvasSize * .72)),
                ([System.Drawing.PointF]::new($canvasSize * .27, $canvasSize * .72)))
            $graphics.FillPolygon($white, $stripeOne)
            $graphics.FillPolygon($white, $stripeTwo)

            $base = New-RoundedRectangle ($canvasSize * .19) ($canvasSize * .75) ($canvasSize * .62) ($canvasSize * .13) ($canvasSize * .04)
            try { $graphics.FillPath($orange, $base) } finally { $base.Dispose() }
        } finally {
            $orange.Dispose()
            $white.Dispose()
        }

        $final = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $finalGraphics = [System.Drawing.Graphics]::FromImage($final)
        try {
            $finalGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $finalGraphics.DrawImage($bitmap, 0, 0, $size, $size)
            $final.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $finalGraphics.Dispose()
            $final.Dispose()
        }
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

foreach ($size in @(16, 32, 48, 128)) {
    New-BridgeIcon $size (Join-Path $iconsDirectory "icon$size.png")
}

$manifest = Get-Content (Join-Path $extensionDirectory 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -ne $Version) { throw "Version du manifeste inattendue : $($manifest.version)" }

$localDirectory = Join-Path $outputsDirectory "JellyfinVlcBridge-Extension-$Version-Local"
$localPackage = Join-Path $outputsDirectory "JellyfinVlcBridge-Extension-$Version-Local.zip"
if (Test-Path -LiteralPath $localDirectory) { Remove-Item -LiteralPath $localDirectory -Recurse -Force }
New-Item -ItemType Directory -Path $localDirectory -Force | Out-Null
Copy-Item (Join-Path $extensionDirectory '*') $localDirectory -Recurse -Force
Compress-Archive -Path (Join-Path $localDirectory '*') -DestinationPath $localPackage -CompressionLevel Optimal -Force

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$stagingDirectory = Join-Path $temporaryRoot ('JellyfinVlcBridgeExtension-' + [Guid]::NewGuid().ToString('N'))
$resolvedStaging = [IO.Path]::GetFullPath($stagingDirectory)
if (-not $resolvedStaging.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFileName($resolvedStaging)).StartsWith('JellyfinVlcBridgeExtension-', [StringComparison]::Ordinal)) {
    throw 'Chemin temporaire inattendu.'
}

try {
    New-Item -ItemType Directory -Path $resolvedStaging -Force | Out-Null
    Copy-Item (Join-Path $extensionDirectory '*') $resolvedStaging -Recurse -Force

    # Le Chrome Web Store attribue lui-même la clé et refuse le champ "key" à l'importation.
    # La version de développement conserve ce champ pour garder son identifiant local stable.
    $storeManifestPath = Join-Path $resolvedStaging 'manifest.json'
    $storeManifest = Get-Content $storeManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $storeManifest.PSObject.Properties.Remove('key')
    $storeJson = $storeManifest | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($storeManifestPath, $storeJson, (New-Object Text.UTF8Encoding($false)))

    $package = Join-Path $outputsDirectory "JellyfinVlcBridge-Extension-$Version-ChromeWebStore.zip"
    Compress-Archive -Path (Join-Path $resolvedStaging '*') -DestinationPath $package -CompressionLevel Optimal -Force
    Write-Output $localDirectory
    Write-Output $localPackage
    Write-Output $package
} finally {
    if (Test-Path -LiteralPath $resolvedStaging) {
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}
