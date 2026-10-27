# tools/windows/stage.ps1 で集めたフォルダのエンジンが，そのフォルダの DLL だけで起動できるかを確かめる．
# ビルドでは llama.cpp の場所を PATH に足しているので，DLL を集め損ねても手元と CI では気づけない．
# PATH を Windows のフォルダだけにして起動し，決めた時間のあいだ落ちなければよいとする
#
# 使い方: tools/windows/check_stage.ps1 -Stage <集めたフォルダ>
param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [int]$Seconds = 10
)

$ErrorActionPreference = 'Stop'
$engine = Join-Path (Resolve-Path $Stage) 's90-engine-host.exe'
if (-not (Test-Path $engine)) { throw "$engine がありません" }
# エンジンがすでに動いていると，2 つ目はすぐに終わる(終了コード 0)ので確かめられない
if (Get-Process -Name 's90-engine-host' -ErrorAction SilentlyContinue) { throw 's90-engine-host がすでに動いています．止めてから確かめてください' }

$info = New-Object System.Diagnostics.ProcessStartInfo $engine
$info.UseShellExecute = $false
$info.WorkingDirectory = Split-Path $engine
$info.EnvironmentVariables['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
$process = [System.Diagnostics.Process]::Start($info)
try {
    if ($process.WaitForExit($Seconds * 1000)) {
        # 0xC0000135 は DLL が見つからないとき
        throw ('エンジンが起動直後に終わりました(終了コード 0x{0:X8})．足りない DLL がないか確かめてください' -f $process.ExitCode)
    }
} finally {
    if (-not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit()
    }
    # エンジンが起動した候補ウィンドウも止める
    Get-Process -Name 's90-candidate-ui' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith((Split-Path $engine), [System.StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force
}
Write-Host "ok: $engine は $Seconds 秒のあいだ動き続けました"
