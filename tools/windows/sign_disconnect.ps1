# tools/windows/sign_connect.ps1 で使えるようにした証明書を，使えない状態に戻す．署名が途中で失敗しても必ず動かす．
#
# certum: SimplySign のセッションを切る(証明書がストアから外れる)
# test:   使い捨ての証明書を，ストアと信頼するルートから消す
#
# 使い方: tools/windows/sign_disconnect.ps1 -Provider certum
#         tools/windows/sign_disconnect.ps1 -Provider test
param(
    [Parameter(Mandatory = $true)][ValidateSet('certum', 'test')][string]$Provider
)

$ErrorActionPreference = 'Stop'
$simplySignExe = Join-Path $env:ProgramFiles 'Certum\SimplySign Desktop\SimplySignDesktop.exe'
$testSubject = 'CN=Hajime IME signing test'
# セッションを切るのを待つ時間(ミリ秒)
$closeWaitMilliseconds = 15000

if ($Provider -eq 'certum') {
    if (Test-Path -LiteralPath $simplySignExe) {
        $process = Start-Process -FilePath $simplySignExe -ArgumentList '/close' -PassThru -ErrorAction SilentlyContinue
        if ($process) { [void]$process.WaitForExit($closeWaitMilliseconds) }
        Get-Process SimplySignDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'ok: SimplySign のセッションを切りました'
} else {
    foreach ($location in 'Cert:\CurrentUser\My', 'Cert:\LocalMachine\Root') {
        Get-ChildItem $location -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq $testSubject } | Remove-Item -Force
    }
    Write-Host 'ok: 使い捨ての証明書を消しました'
}
