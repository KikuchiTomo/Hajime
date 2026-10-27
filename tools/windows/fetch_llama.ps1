# Zenzai が使う llama.cpp の Windows 向けのビルド(b4846．AVX 版)を取得し，SHA-256 を確かめて展開する．
# エンジン(core)の AzooKeyKanaKanjiConverter は Windows では llama.cpp をシステムのライブラリとして探すので，
# 展開した場所を LIB(リンク時の llama.lib)と PATH(実行時の llama.dll・ggml*.dll)に足して使う．
# ggml.dll は ggml-rpc.dll も読み込むので，配布物にはこれも入れる(tools/windows/stage.ps1)．
# バージョンを変えるときは，AzooKeyKanaKanjiConverter の llama.cpp のヘッダーのバージョンと合わせ，ハッシュを取り直す．
#
# 使い方: tools/windows/fetch_llama.ps1 -Output <展開する場所>
param(
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
# 上流の azooKey-Windows と同じビルド(MIT．THIRD_PARTY_NOTICES.md の llama.cpp)
$url = 'https://github.com/fkunn1326/llama.cpp/releases/download/b4846/llama-b4846-bin-win-avx-x64.zip'
$expected = 'af34e4dfc7154df650ed705421f26b3a56c685f2e35abfdd6df0cc0cb5c4b259'

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$archive = Join-Path ([System.IO.Path]::GetTempPath()) "llama-b4846-$([guid]::NewGuid()).zip"
try {
    Invoke-WebRequest -Uri $url -OutFile $archive
    $actual = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "llama.cpp の SHA-256 が一致しません: $actual" }
    Expand-Archive -Path $archive -DestinationPath $Output -Force
} finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $archive
}
foreach ($file in @('llama.lib', 'llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-cpu.dll', 'ggml-rpc.dll')) {
    if (-not (Test-Path (Join-Path $Output $file))) { throw "$file がありません" }
}
Write-Host "確かめました: $Output"
