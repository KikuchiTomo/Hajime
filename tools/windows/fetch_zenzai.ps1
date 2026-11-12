# Zenzai と jinen のモデル(それぞれ small と xsmall)を取得し，SHA-256 を確かめる(tools/models/fetch_zenzai.sh の Windows 版)．
# 取得元とハッシュは fetch_zenzai.sh・core/Sources/HajimeEngine/ZenzaiModel.swift・JinenModel.swift と同じ値にする．
#
# 使い方: tools/windows/fetch_zenzai.ps1 -Output <置く場所>
param(
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Output | Out-Null

# 1 つのモデルを取って確かめる．Hugging Face(コミットを固定)から取れないときは，同じファイルを置いた GitHub の Releases から取る
function Get-Model([string]$File, [string]$Url, [string]$Mirror, [string]$Expected) {
    $destination = Join-Path $Output $File
    if (-not (Test-Path $destination)) {
        $download = "$destination.download"
        try {
            Invoke-WebRequest -Uri $Url -OutFile $download
        } catch {
            Write-Host "Hugging Face から取れなかったので，予備の取得元から取ります: $File"
            Invoke-WebRequest -Uri $Mirror -OutFile $download
        }
        Move-Item -Force $download $destination
    }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $destination).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) {
        Remove-Item -Force $destination
        throw "モデルの SHA-256 が一致しません: $File $actual"
    }
    Write-Host "確かめました: $destination"
}

# Miwa-Keita/zenz-v3.2-small-gguf(Apache-2.0)
Get-Model 'zenz-v3.2-small-Q5_K_M.gguf' `
    'https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf' `
    'https://github.com/KikuchiTomo/Hajime/releases/download/models%2Fzenz-v3.2-small-c67e03e/zenz-v3.2-small-Q5_K_M.gguf' `
    '29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673'
# Miwa-Keita/zenz-v3.2-xsmall-gguf(Apache-2.0)．設定の「Zenzai のモデル」で速さを優先するときと併用するときに使う
Get-Model 'zenz-v3.2-xsmall-Q5_K_M.gguf' `
    'https://huggingface.co/Miwa-Keita/zenz-v3.2-xsmall-gguf/resolve/4f5423f0fad41a73b1242eb96fe5c12ae4fdca83/ggml-model-Q5_K_M.gguf' `
    'https://github.com/KikuchiTomo/Hajime/releases/download/models%2Fzenz-v3.2-xsmall-4f5423f/zenz-v3.2-xsmall-Q5_K_M.gguf' `
    '00c64b3d318045a708d0cad5434faccab10f5481a49e6362864551fd0995fa58'
# togatogah/jinen-v2-small.gguf(CC BY-SA 4.0．国立国会図書館の書誌データを加工して作られている．THIRD_PARTY_NOTICES.md)．合議に使う
Get-Model 'jinen-v2-small-Q5_K_M.gguf' `
    'https://huggingface.co/togatogah/jinen-v2-small.gguf/resolve/3461d0573ab447985badde3174165b967d06076c/jinen-v2-small-Q5_K_M.gguf' `
    'https://github.com/KikuchiTomo/Hajime/releases/download/models%2Fjinen-v2-small-3461d05/jinen-v2-small-Q5_K_M.gguf' `
    '80482707513d6b67dafc31774371cf95d765542abf8d74eebf5f32f92d788bd3'
# togatogah/jinen-v2-xsmall.gguf(CC BY-SA 4.0)．合議で，遅い環境(GPU の無い PC)に使う
Get-Model 'jinen-v2-xsmall-Q5_K_M.gguf' `
    'https://huggingface.co/togatogah/jinen-v2-xsmall.gguf/resolve/3910fd01bf4ba86eca89617f18db9b0c1c5b2283/jinen-v2-xsmall-Q5_K_M.gguf' `
    'https://github.com/KikuchiTomo/Hajime/releases/download/models%2Fjinen-v2-xsmall-3910fd0/jinen-v2-xsmall-Q5_K_M.gguf' `
    '24ff3af5db712fbbb4aa9254ee28ec4d731207134471ab68b06c1828726284c2'
