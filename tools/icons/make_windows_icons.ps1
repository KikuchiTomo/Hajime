# Windows のアプリのアイコン(設定の画面・入力の一覧に出す IME のアイコン)を作る．
# 使い方: tools/icons/make_windows_icons.ps1 [-Output apps/windows/resources]
#
# 形は macOS の入力メニューのアイコン(tools/icons/make_input_icons.swift)と同じにする．
# 角丸の面に「あ」を置き，右下の角だけ丸めず，分岐図の幹から枝が出る角に見立てる．
# macOS はテンプレート画像(色は OS が付ける)だが，Windows のアプリのアイコンは色を持つので，
# 暗い面に白い字を置き，暗いタスクバーでも形が見えるよう縁に薄い線を引く．
# 字は配布物に入れている Kiwi Maru(SIL OFL 1.1．data/fonts)で描く．OS の書体は画像にして配る条件が書体ごとに違うため使わない．
# 依存を増やさないよう，Windows に入っている System.Drawing(GDI+)で描き，ICO は PNG を並べて自分で組み立てる
param(
    [string]$Output = (Join-Path $PSScriptRoot '..\..\apps\windows\resources')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$fontFile = Join-Path $root 'data\fonts\KiwiMaru-Medium.ttf'
if (-not (Test-Path $fontFile)) { throw "$fontFile がありません" }

# 16 を 1 としたときの寸法(make_input_icons.swift と同じ比)
$canvas = 16.0
$radius = 3.5
$glyphSize = 11.5
# 面と字と縁の色
$plateColor = [System.Drawing.Color]::FromArgb(255, 0x1C, 0x1C, 0x1E)
$glyphColor = [System.Drawing.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF)
$edgeColor = [System.Drawing.Color]::FromArgb(56, 0xFF, 0xFF, 0xFF)
# ICO に入れる大きさ(Windows が使う大きさ．タスクバー・タイトルバー・一覧・大きいアイコン)
$sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)

$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile($fontFile)
$family = $fonts.Families[0]

# 右下の角だけ丸めない角丸の長方形
function New-Plate([single]$x, [single]$y, [single]$size, [single]$r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $size - $d, $y, $d, $d, 270, 90)
    $path.AddLine($x + $size, $y + $size, $x + $size, $y + $size)
    $path.AddArc($x, $y + $size - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $path
}

function New-IconPng([int]$pixels) {
    $scale = $pixels / $canvas
    $bitmap = New-Object System.Drawing.Bitmap $pixels, $pixels, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $plate = New-Plate 0 0 $pixels ($radius * $scale)
    $brush = New-Object System.Drawing.SolidBrush $plateColor
    $graphics.FillPath($brush, $plate)
    # 縁は 1 ピクセル内側に引く(外にはみ出すと切れる)
    $inset = 0.5
    $edge = New-Plate $inset $inset ($pixels - 1) ([Math]::Max(0.5, $radius * $scale - $inset))
    $pen = New-Object System.Drawing.Pen $edgeColor, 1
    $graphics.DrawPath($pen, $edge)

    # 字は字面(見た目の範囲)で面の中央にそろえる
    $glyph = New-Object System.Drawing.Drawing2D.GraphicsPath
    $format = [System.Drawing.StringFormat]::GenericTypographic
    $glyph.AddString('あ', $family, [int][System.Drawing.FontStyle]::Regular, [single]($glyphSize * $scale), (New-Object System.Drawing.PointF 0, 0), $format)
    $bounds = $glyph.GetBounds()
    $matrix = New-Object System.Drawing.Drawing2D.Matrix
    $matrix.Translate(($pixels - $bounds.Width) / 2 - $bounds.X, ($pixels - $bounds.Height) / 2 - $bounds.Y)
    $glyph.Transform($matrix)
    $glyphBrush = New-Object System.Drawing.SolidBrush $glyphColor
    $graphics.FillPath($glyphBrush, $glyph)

    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    foreach ($item in @($glyphBrush, $glyph, $matrix, $pen, $edge, $brush, $plate, $graphics, $bitmap)) { $item.Dispose() }
    , $stream.ToArray()
}

# ICO: ICONDIR(6 バイト)と ICONDIRENTRY(16 バイト)を並べ，そのあとに PNG を置く
$images = foreach ($size in $sizes) { , (New-IconPng $size) }
$ico = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter $ico
$writer.Write([uint16]0)
$writer.Write([uint16]1)
$writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dimension = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $writer.Write([byte]$dimension)
    $writer.Write([byte]$dimension)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$images[$i].Length)
    $writer.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($image in $images) { $writer.Write($image) }
$writer.Flush()

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$target = Join-Path (Resolve-Path $Output) 's90.ico'
[System.IO.File]::WriteAllBytes($target, $ico.ToArray())
# 見本: 大きさごとに並べた PNG(design/mockups に置いて見比べる)
$previewSizes = @(16, 24, 32, 48, 256)
$width = [int](($previewSizes | Measure-Object -Sum).Sum + 16 * ($previewSizes.Count + 1))
$preview = New-Object System.Drawing.Bitmap $width, ([int](256 + 32))
$graphics = [System.Drawing.Graphics]::FromImage($preview)
$graphics.Clear([System.Drawing.Color]::FromArgb(255, 0x20, 0x20, 0x20))
$x = 16
foreach ($size in $previewSizes) {
    $index = [Array]::IndexOf($sizes, $size)
    $image = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream (, $images[$index])))
    $graphics.DrawImage($image, $x, 16 + 256 - $size, $size, $size)
    $image.Dispose()
    $x += $size + 16
}
$graphics.Dispose()
$previewPath = Join-Path $root 'design\mockups\windows-app-icon.png'
$preview.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
$preview.Dispose()
Write-Host "ok: $target と $previewPath を書きました"
