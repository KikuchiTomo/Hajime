param(
    [Parameter(Mandatory = $true)][string]$Output,
    # tools/windows/fetch_llama.ps1 で展開した llama.cpp の場所
    [Parameter(Mandatory = $true)][string]$Llama,
    # tools/windows/fetch_zenzai.ps1 でモデルを置いた場所
    [Parameter(Mandatory = $true)][string]$Zenzai
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$rust = Join-Path $root 'apps\windows\target'
$swift = Join-Path $root 'core\.build\x86_64-unknown-windows-msvc\release'

New-Item -ItemType Directory -Force -Path $Output | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Output 'x86') | Out-Null

Copy-Item (Join-Path $rust 'release\hajime_tsf.dll') $Output
Copy-Item (Join-Path $rust 'release\hajime-candidate-ui.exe') $Output
Copy-Item (Join-Path $rust 'release\hajime-settings.exe') $Output
Copy-Item (Join-Path $rust 'i686-pc-windows-msvc\release\hajime_tsf.dll') (Join-Path $Output 'x86')

Copy-Item (Join-Path $swift 'hajime-engine-host.exe') $Output
Get-ChildItem -Path $swift -File -Filter '*.dll' | Copy-Item -Destination $Output
Get-ChildItem -Path $swift -Directory -Filter '*.resources' | Copy-Item -Destination $Output -Recurse

$runtime = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Swift\Runtimes') -Directory | Sort-Object Name | Select-Object -Last 1
if (-not $runtime) { throw 'Swift のランタイムが見つかりません' }
Get-ChildItem -Path (Join-Path $runtime.FullName 'usr\bin') -Filter '*.dll' | Copy-Item -Destination $Output

# Zenzai が使う llama.cpp の DLL と，確かめ済みのモデル(エンジンは Zenzai\ から読み，ハッシュを確かめ直す)．
# ggml.dll は ggml-rpc.dll を読み込むので，これが無いとエンジンが起動しない(0xC0000135)
foreach ($file in @('llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-cpu.dll', 'ggml-rpc.dll')) {
    Copy-Item (Join-Path $Llama $file) $Output
}
New-Item -ItemType Directory -Force -Path (Join-Path $Output 'Zenzai') | Out-Null
Copy-Item (Join-Path $Zenzai 'zenz-v3.2-small-Q5_K_M.gguf') (Join-Path $Output 'Zenzai')

Copy-Item (Join-Path $root 'data\postal\postal-codes.tsv') $Output
Copy-Item (Join-Path $root 'data\thesaurus\wordnet-ja.tsv') $Output
# 候補ウィンドウの既定の書体(Kiwi Maru．SIL OFL 1.1)．候補ウィンドウと設定の画面が fonts\ から読む
Copy-Item (Join-Path $root 'data\fonts') (Join-Path $Output 'fonts') -Recurse -Force
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $Output 'LICENSE.txt')
Copy-Item (Join-Path $root 'THIRD_PARTY_NOTICES.md') (Join-Path $Output 'THIRD_PARTY_NOTICES.md')
Copy-Item (Join-Path $root 'LICENSES') (Join-Path $Output 'LICENSES') -Recurse -Force

$required = @('hajime_tsf.dll', 'x86\hajime_tsf.dll', 'hajime-engine-host.exe', 'hajime-candidate-ui.exe', 'hajime-settings.exe', 'postal-codes.tsv', 'wordnet-ja.tsv',
    'llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-cpu.dll', 'ggml-rpc.dll', 'Zenzai\zenz-v3.2-small-Q5_K_M.gguf', 'LICENSES\Apache-2.0.txt',
    'fonts\KiwiMaru-Regular.ttf', 'fonts\KiwiMaru-Medium.ttf', 'LICENSES\OFL-1.1-KiwiMaru.txt')
foreach ($file in $required) {
    if (-not (Test-Path (Join-Path $Output $file))) { throw "$file がありません" }
}
Write-Host "ok: $Output に集めました"
