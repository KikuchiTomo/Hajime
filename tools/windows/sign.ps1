# 集めたフォルダの EXE と DLL，またはインストーラー(MSI)に，コード署名(Authenticode)と時刻印(RFC 3161)を付ける．
# Microsoft Store は，インストーラーと中のすべての EXE・DLL に署名があることを求める(Store Policies 10.2.9)．
# Windows 11 の Smart App Control も，署名の無いプログラムを止める．
#
# 署名するのは，署名がまだ無いファイルだけ(Microsoft の署名がある Visual C++ の実行環境などは触らない)．
# Hajime IME の EXE・DLL のほか，同梱する Swift の実行環境や llama.cpp の DLL も署名が無いので，同じ証明書で署名する．
# 順番: 集めたフォルダの EXE・DLL に署名する → インストーラーを作る → インストーラーに署名する．
#
# 証明書は tools/windows/sign_connect.ps1 が証明書ストア(CurrentUser\My)で使えるようにしたものを拇印で選ぶ．鍵そのものは扱わない．
# 時刻印を付けるので，証明書の期限が切れたあとも署名は有効なまま．
#
# 使い方:
#   tools/windows/sign.ps1 -Path <集めたフォルダ か .msi のあるフォルダ> [-Include exe,dll | msi] [-Thumbprint <拇印>]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string[]]$Include = @('exe', 'dll'),
    # 省くと，sign_connect.ps1 が環境変数 HAJIME_SIGN_THUMBPRINT に入れた拇印を使う
    [string]$Thumbprint = $env:HAJIME_SIGN_THUMBPRINT,
    # 署名の時刻を証明するサーバー(Certum が無料で公開している)
    [string]$TimestampUrl = 'http://time.certum.pl'
)

$ErrorActionPreference = 'Stop'
# ユーザーアカウント制御の確認に出る名前と，そのリンク先．付けないと，インストーラーは一時ファイルの名前で表示される
$description = 'Hajime IME'
$descriptionUrl = 'https://haji.men'
$attempts = 4

if ($Thumbprint -notmatch '^[0-9A-Fa-f]{40}$') { throw '証明書の拇印がありません．先に tools/windows/sign_connect.ps1 を動かしてください' }
$Thumbprint = $Thumbprint.ToUpperInvariant()

$root = (Resolve-Path $Path).Path
$patterns = $Include | ForEach-Object { "*.$_" }
$files = @(Get-ChildItem -Path $root -Recurse -File -Include $patterns | Sort-Object FullName)
if ($files.Count -eq 0) { throw "$root に署名の対象(.$($Include -join '・.'))がありません" }

# 署名がまだ無いファイルを選ぶ．有効な署名があるものは，ほかの発行元のものなので触らない．
# 署名が壊れているものは，上から署名せずに止める(作り直すべきもの)
$unsigned = @(foreach ($file in $files) {
        $status = (Get-AuthenticodeSignature -LiteralPath $file.FullName).Status
        if ($status -eq 'NotSigned') { $file.FullName }
        elseif ($status -ne 'Valid') { throw "$($file.FullName) の署名を確かめられません($status)" }
    })
Write-Host "対象 $($files.Count) 個のうち，署名の要るファイルは $($unsigned.Count) 個"
foreach ($file in $unsigned) { Write-Host "  $($file.Substring($root.Length).TrimStart('\'))" }
if ($unsigned.Count -eq 0) { return }

# signtool は Windows SDK に入っている．いちばん新しいバージョンの x64 を使う
$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.*\x64\signtool.exe" -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1
if (-not $signtool) { throw 'signtool.exe(Windows SDK)が見つかりません' }

# 1 回の呼び出しでまとめて署名する．時刻印のサーバーやクラウドの鍵が一時的に応えないことがあるので，間をあけてやり直す
$arguments = @('sign', '/fd', 'SHA256', '/sha1', $Thumbprint, '/tr', $TimestampUrl, '/td', 'SHA256', '/d', $description, '/du', $descriptionUrl) + $unsigned
for ($attempt = 1; ; $attempt++) {
    & $signtool.FullName @arguments
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -ge $attempts) { throw "署名できませんでした(signtool の終了コード $LASTEXITCODE)" }
    Write-Host "署名できませんでした(signtool の終了コード $LASTEXITCODE)．やり直します"
    Start-Sleep -Seconds (10 * $attempt)
}

# 署名が Windows に信頼され，使うはずの証明書のもので，時刻印が付いていることを 1 つずつ確かめる
foreach ($file in $unsigned) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if ($signature.Status -ne 'Valid') { throw "$file の署名を確かめられません: $($signature.Status) $($signature.StatusMessage)" }
    if ($signature.SignerCertificate.Thumbprint -ne $Thumbprint) { throw "$file の署名が，使うはずの証明書のものではありません" }
    if (-not $signature.TimeStamperCertificate) { throw "$file に時刻印がありません" }
}
Write-Host "ok: $($unsigned.Count) 個に署名しました"
