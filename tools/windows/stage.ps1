param(
    [Parameter(Mandatory = $true)][string]$Output,
    # tools/windows/build_llama.ps1 でビルドした llama.cpp の場所
    [Parameter(Mandatory = $true)][string]$Llama,
    # tools/windows/fetch_zenzai.ps1 でモデル(Zenzai と jinen)を置いた場所
    [Parameter(Mandatory = $true)][string]$Zenzai,
    # tools/dictionary/fetch_dictionary.ps1 で展開した hajime-dictionary-<版> の場所
    [Parameter(Mandatory = $true)][string]$Dictionary
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
# CPU の命令ごとの ggml-cpu-*.dll は，エンジンが llama.dll と同じ場所から合うものを選んで読む
foreach ($file in @('llama.dll', 'ggml.dll', 'ggml-base.dll')) {
    Copy-Item (Join-Path $Llama $file) $Output
}
Get-ChildItem -Path $Llama -File -Filter 'ggml-cpu-*.dll' | Copy-Item -Destination $Output
New-Item -ItemType Directory -Force -Path (Join-Path $Output 'Zenzai') | Out-Null
Copy-Item (Join-Path $Zenzai 'zenz-v3.2-small-Q5_K_M.gguf') (Join-Path $Output 'Zenzai')
Copy-Item (Join-Path $Zenzai 'zenz-v3.2-xsmall-Q5_K_M.gguf') (Join-Path $Output 'Zenzai')
# 合議(ADR 0016 の案 2)に使う Jinen モデル(エンジンは Jinen\ から読み，ハッシュを確かめ直す)．CC BY-SA 4.0(THIRD_PARTY_NOTICES.md)
New-Item -ItemType Directory -Force -Path (Join-Path $Output 'Jinen') | Out-Null
Copy-Item (Join-Path $Zenzai 'jinen-v2-small-Q5_K_M.gguf') (Join-Path $Output 'Jinen')
Copy-Item (Join-Path $Zenzai 'jinen-v2-xsmall-Q5_K_M.gguf') (Join-Path $Output 'Jinen')

# かな漢字変換の辞書(エンジンは Dictionary\ から読み，ファイルごとのハッシュを確かめ直す)と，辞書のライセンスの表示
# 辞書には [0022].louds のように角かっこを含む名前のファイルがあるので，ワイルドカードとして読まない -LiteralPath で写す
Copy-Item -LiteralPath (Join-Path $Dictionary 'Dictionary') -Destination (Join-Path $Output 'Dictionary') -Recurse -Force

Copy-Item (Join-Path $root 'data\postal\postal-codes.tsv') $Output
Copy-Item (Join-Path $root 'data\thesaurus\wordnet-ja.tsv') $Output
Copy-Item (Join-Path $root 'data\usage\usage_dict.txt') $Output
Copy-Item (Join-Path $root 'data\usage\usage_dict_extra.tsv') $Output
Copy-Item (Join-Path $root 'data\usage\usage_dict_words.tsv') $Output
Copy-Item (Join-Path $root 'data\english\english-terms.txt') $Output
Copy-Item (Join-Path $root 'data\palette\palette.tsv') $Output
Copy-Item (Join-Path $root 'data\palette\emoji-synonyms.tsv') $Output
# 候補ウィンドウの既定の書体(Kiwi Maru．SIL OFL 1.1)．候補ウィンドウと設定の画面が fonts\ から読む
Copy-Item (Join-Path $root 'data\fonts') (Join-Path $Output 'fonts') -Recurse -Force
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $Output 'LICENSE.txt')
Copy-Item (Join-Path $root 'THIRD_PARTY_NOTICES.md') (Join-Path $Output 'THIRD_PARTY_NOTICES.md')
Copy-Item (Join-Path $root 'LICENSES') (Join-Path $Output 'LICENSES') -Recurse -Force
New-Item -ItemType Directory -Force -Path (Join-Path $Output 'LICENSES\hajime-dictionary') | Out-Null
Copy-Item (Join-Path $Dictionary 'NOTICE.md') (Join-Path $Output 'LICENSES\hajime-dictionary')
Copy-Item (Join-Path $Dictionary 'LICENSES\*') (Join-Path $Output 'LICENSES\hajime-dictionary')

$required = @('hajime_tsf.dll', 'x86\hajime_tsf.dll', 'hajime-engine-host.exe', 'hajime-candidate-ui.exe', 'hajime-settings.exe', 'postal-codes.tsv', 'wordnet-ja.tsv', 'usage_dict.txt', 'usage_dict_extra.tsv', 'usage_dict_words.tsv', 'english-terms.txt', 'palette.tsv', 'emoji-synonyms.tsv',
    'llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-cpu-x64.dll', 'ggml-cpu-sandybridge.dll', 'ggml-cpu-haswell.dll', 'Zenzai\zenz-v3.2-small-Q5_K_M.gguf', 'Zenzai\zenz-v3.2-xsmall-Q5_K_M.gguf',
    'Jinen\jinen-v2-small-Q5_K_M.gguf', 'Jinen\jinen-v2-xsmall-Q5_K_M.gguf', 'LICENSES\Apache-2.0.txt',
    'Dictionary\SHA256SUMS', 'Dictionary\louds\charID.chid', 'LICENSES\hajime-dictionary\NOTICE.md', 'LICENSES\hajime-dictionary\Mozc-LICENSE.txt', 'LICENSES\hajime-dictionary\mozcdic-ut-LICENSE.txt',
    'fonts\KiwiMaru-Regular.ttf', 'fonts\KiwiMaru-Medium.ttf', 'LICENSES\OFL-1.1-KiwiMaru.txt')
foreach ($file in $required) {
    if (-not (Test-Path (Join-Path $Output $file))) { throw "$file がありません" }
}
Write-Host "ok: $Output に集めました"
