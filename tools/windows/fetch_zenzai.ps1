# Zenzai のモデルを取得し，SHA-256 を確かめる(tools/models/fetch_zenzai.sh の Windows 版)．
# 取得元とハッシュは fetch_zenzai.sh・core/Sources/S90Engine/ZenzaiModel.swift と同じ値にする．
#
# 使い方: tools/windows/fetch_zenzai.ps1 -Output <置く場所>
param(
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
$file = 'zenz-v3.2-small-Q5_K_M.gguf'
# Hugging Face の Miwa-Keita/zenz-v3.2-small-gguf(Apache-2.0)．コミットを固定する
$url = 'https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf/resolve/c67e03e07d215c869f591b274c1631170d3e11fe/ggml-model-Q5_K_M.gguf'
# 予備の取得元．Hugging Face から取れないときに使う
$mirror = "https://github.com/KikuchiTomo/s90.tokyo-IME/releases/download/models%2Fzenz-v3.2-small-c67e03e/$file"
$expected = '29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673'

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$destination = Join-Path $Output $file
if (-not (Test-Path $destination)) {
    $download = "$destination.download"
    try {
        Invoke-WebRequest -Uri $url -OutFile $download
    } catch {
        Write-Host 'Hugging Face から取れなかったので，予備の取得元から取ります'
        Invoke-WebRequest -Uri $mirror -OutFile $download
    }
    Move-Item -Force $download $destination
}
$actual = (Get-FileHash -Algorithm SHA256 -Path $destination).Hash.ToLowerInvariant()
if ($actual -ne $expected) {
    Remove-Item -Force $destination
    throw "Zenzai のモデルの SHA-256 が一致しません: $actual"
}
Write-Host "確かめました: $destination"
