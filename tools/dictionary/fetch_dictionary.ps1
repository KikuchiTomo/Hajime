# かな漢字変換の辞書(hajime-dictionary)を取得し，SHA-256 を確かめて展開する(tools/dictionary/fetch_dictionary.sh の Windows 版)．
# 版とハッシュは fetch_dictionary.sh・core/Sources/HajimeEngine/BundledDictionary.swift と同じ値にする．
#
# 使い方: tools/dictionary/fetch_dictionary.ps1 -Output <置く場所>
# 置く場所の hajime-dictionary-<版>\Dictionary に展開する
param(
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
$version = '0.1.1'
$url = "https://github.com/KikuchiTomo/hajime-dictionary/releases/download/v$version/hajime-dictionary-$version.tar.gz"
$expected = '339f7a715b7d8b509b38e754ab5f8010a0e985c726de47255833486280d0f32b'
# 展開した Dictionary\SHA256SUMS の SHA-256(BundledDictionary.expectedManifestSHA256 と同じ値)
$manifest = '8b73e404747c801017c9ca37219bb9ba97702939ef29822e704f741d2c827779'

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$directory = Join-Path $Output "hajime-dictionary-$version"
$sums = Join-Path $directory 'Dictionary\SHA256SUMS'
if ((Test-Path -LiteralPath $sums) -and ((Get-FileHash -Algorithm SHA256 -LiteralPath $sums).Hash.ToLowerInvariant() -eq $manifest)) {
    Write-Host "確かめました: $directory\Dictionary"
    exit 0
}
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("hajime-dictionary-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    $archive = Join-Path $work 'dictionary.tar.gz'
    Invoke-WebRequest -Uri $url -OutFile $archive
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "辞書の SHA-256 が一致しません: $actual" }
    # Windows 10 以降に入っている tar(bsdtar)で展開する
    tar -xzf $archive -C $work
    if ($LASTEXITCODE -ne 0) { throw '辞書を展開できません' }
    $extracted = Join-Path $work "hajime-dictionary-$version"
    $extractedSums = Join-Path $extracted 'Dictionary\SHA256SUMS'
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $extractedSums).Hash.ToLowerInvariant() -ne $manifest) { throw '辞書の一覧の SHA-256 が一致しません' }
    # 辞書には [0022].louds のように角かっこを含む名前のファイルがある．-Path はワイルドカードとして読むので，-LiteralPath で開く
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $extractedSums) {
        $hash, $path = $line -split '  ', 2
        $file = Join-Path (Join-Path $extracted 'Dictionary') ($path -replace '/', '\')
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant() -ne $hash) { throw "辞書のファイルの SHA-256 が一覧と一致しません: $path" }
    }
    if (Test-Path $directory) { Remove-Item -Recurse -Force $directory }
    Move-Item $extracted $directory
} finally {
    if (Test-Path $work) { Remove-Item -Recurse -Force $work }
}
Write-Host "確かめました: $directory\Dictionary"
