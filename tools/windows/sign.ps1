# 集めたフォルダの EXE と DLL，またはインストーラー(MSI)にコード署名(Authenticode)を付ける．
# Microsoft Store は，インストーラーと中のすべての EXE・DLL に署名があることを求める(Store Policies 10.2.9)．
# Windows 11 の Smart App Control も，署名の無いプログラムを止める．
#
# 署名するのは，有効な署名がまだ無いファイルだけ(Microsoft の署名がある Visual C++ の実行環境などは触らない)．
# Hajime IME の EXE・DLL のほか，同梱する Swift の実行環境や llama.cpp の DLL も署名が無いので，同じ証明書で署名する．
# 順番: 集めたフォルダの EXE・DLL に署名する → インストーラーを作る → インストーラーに署名する．
#
# 証明書は，実行する利用者の証明書ストア(CurrentUser\My)にあるものを拇印(-Thumbprint)で選ぶ．鍵そのものは扱わない．
# -Thumbprint を渡さないとき(証明書をまだ用意していないとき)は，署名の要るファイルを数えて並べるだけで何も変えない．
#
# 使い方:
#   tools/windows/sign.ps1 -Path <集めたフォルダ か .msi のあるフォルダ> [-Include exe,dll | msi] [-Thumbprint <拇印>]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string[]]$Include = @('exe', 'dll'),
    [string]$Thumbprint = '',
    # 署名の時刻を証明するサーバー(RFC 3161)．証明書の期限が切れたあとも署名を有効に保つ
    [string]$TimestampUrl = 'http://time.certum.pl'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $Path).Path
$patterns = $Include | ForEach-Object { "*.$_" }
$files = @(Get-ChildItem -Path $root -Recurse -File -Include $patterns | Sort-Object FullName)
if ($files.Count -eq 0) { throw "$root に署名の対象(.$($Include -join '・.'))がありません" }

# 有効な署名がまだ無いファイル
$unsigned = @($files | Where-Object { (Get-AuthenticodeSignature -LiteralPath $_.FullName).Status -ne 'Valid' })
Write-Host "対象 $($files.Count) 個のうち，署名の要るファイルは $($unsigned.Count) 個"
foreach ($file in $unsigned) { Write-Host "  $($file.FullName.Substring($root.Length).TrimStart('\'))" }

if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
    Write-Host '拇印(-Thumbprint)が無いので，署名はしません'
    return
}
if ($unsigned.Count -eq 0) { return }

# signtool は Windows SDK に入っている．いちばん新しい版の x64 を使う
$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$signtool = Get-ChildItem -Path $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\x64\signtool\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $signtool) { throw "signtool.exe が $kits にありません(Windows SDK が要ります)" }

# 1 回の呼び出しでまとめて署名する(証明書の鍵を使う確認が 1 回で済む)
$paths = $unsigned | ForEach-Object { $_.FullName }
& $signtool.FullName sign /sha1 $Thumbprint /fd sha256 /tr $TimestampUrl /td sha256 @paths
if ($LASTEXITCODE -ne 0) { throw "署名できませんでした(signtool の終了コード $LASTEXITCODE)" }

# 署名が Windows に信頼されるかを 1 つずつ確かめる
foreach ($file in $paths) {
    & $signtool.FullName verify /pa /q $file
    if ($LASTEXITCODE -ne 0) { throw "署名を確かめられませんでした: $file" }
}
Write-Host "$($paths.Count) 個に署名しました"
