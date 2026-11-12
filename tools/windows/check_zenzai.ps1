# Zenzai が Windows の CPU で動くことを，評価用の文(conversion-basic)を変換して確かめる．
# llama.cpp の CPU の DLL(ggml-cpu-*.dll)を読めないと，エンジンは Zenzai なしで変換するので，テストが通っても気づけない．
# Zenzai なしだと正解が大きく下がる(macOS で 28/29 が 19/29 ほどになる)ので，正解の数で確かめる．
# 時間も書き出す(Windows の CPU での目安．debug でビルドしたものは Swift の部分が遅い)．
#
# 使い方: tools/windows/check_zenzai.ps1 -Zenzai <モデルの場所> -Dictionary <hajime-dictionary-<版> の場所> [-Configuration debug|release] [-ScratchPath <ビルドの場所>]
# ScratchPath は swift build に --scratch-path で渡した場所(渡していなければ省く)
param(
    [Parameter(Mandatory = $true)][string]$Zenzai,
    [Parameter(Mandatory = $true)][string]$Dictionary,
    [string]$Configuration = 'debug',
    [string]$ScratchPath = '',
    [int]$Minimum = 27
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$arguments = @('build', '--package-path', (Join-Path $root 'core'), '-c', $Configuration, '--only-use-versions-from-resolved-file', '--show-bin-path')
if ($ScratchPath) { $arguments += @('--scratch-path', $ScratchPath) }
$bin = (& swift @arguments).Trim()
$playground = Join-Path $bin 'hajime-playground.exe'
if (-not (Test-Path $playground)) { throw "$playground がありません" }

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$file = Join-Path $root 'core\Evaluation\conversion-basic.tsv'
$output = & $playground --evaluate $file --zenzai (Join-Path $Zenzai 'zenz-v3.2-small-Q5_K_M.gguf') --dictionary (Join-Path $Dictionary 'Dictionary') 2>$null
if ($LASTEXITCODE -ne 0) { throw "hajime-playground が終了コード $LASTEXITCODE で終わりました" }
$summary = $output | Select-Object -Last 1
Write-Host $summary
if ($summary -notmatch '(\d+) / (\d+) \(') { throw '評価の結果を読めませんでした' }
$passed = [int]$Matches[1]
if ($passed -lt $Minimum) { throw "Zenzai で変換できていないとみられます(正解 $passed，下限 $Minimum)" }
Write-Host "ok: Zenzai で変換できました(正解 $passed)"
