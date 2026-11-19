# ワンタイムコード(RFC 6238 の TOTP)を計算する関数．tools/windows/sign_connect.ps1 が読み込み，Certum のクラウドへのログインに使う．
# Certum の QR コードは SHA256・6 桁・30 秒を指定している．SHA1 で計算すると違うコードになるので，方式は QR コードの中身(otpauth:// の URI)から読む．
# シークレットキーとコードは，どの関数も表示しない
#
# 使い方: . tools/windows/sign_totp.ps1          関数を読み込む
#         tools/windows/sign_totp.ps1 -Check     RFC 6238 の検証値と合うかを確かめる
param(
    [switch]$Check
)

# otpauth://totp/...?secret=...&algorithm=SHA256&digits=6&period=30 を読む
function ConvertFrom-OtpAuthUri([string]$Uri) {
    $parsed = $null
    if (-not [Uri]::TryCreate($Uri.Trim(), [UriKind]::Absolute, [ref]$parsed) -or $parsed.Scheme -ne 'otpauth' -or $parsed.Host -ne 'totp') {
        throw 'otpauth://totp/ で始まる URI ではありません．QR コードの中身をそのまま入れてください'
    }
    $query = @{}
    foreach ($pair in $parsed.Query.TrimStart('?').Split('&', [StringSplitOptions]::RemoveEmptyEntries)) {
        $parts = $pair.Split('=', 2)
        $value = if ($parts.Count -eq 2) { [Uri]::UnescapeDataString($parts[1]) } else { '' }
        $query[[Uri]::UnescapeDataString($parts[0]).ToLowerInvariant()] = $value
    }
    $secret = ([string]$query['secret']).Trim().TrimEnd('=').ToUpperInvariant()
    if ($secret -notmatch '^[A-Z2-7]{16,}$') { throw 'otpauth の URI に Base32 のシークレットキーがありません' }
    $algorithm = if ($query['algorithm']) { ([string]$query['algorithm']).ToUpperInvariant() } else { 'SHA1' }
    if ($algorithm -notin 'SHA1', 'SHA256', 'SHA512') { throw "対応していない TOTP の方式です: $algorithm" }
    $digits = if ($query['digits']) { [int]$query['digits'] } else { 6 }
    $period = if ($query['period']) { [int]$query['period'] } else { 30 }
    if ($digits -notin 6, 7, 8 -or $period -lt 15 -or $period -gt 120) { throw 'TOTP の桁数か周期が範囲の外です' }
    [pscustomobject]@{ Secret = $secret; Algorithm = $algorithm; Digits = $digits; Period = $period }
}

function ConvertFrom-Base32([string]$Text) {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $buffer = 0
    $bits = 0
    foreach ($character in $Text.TrimEnd('=').ToUpperInvariant().ToCharArray()) {
        $value = $alphabet.IndexOf($character)
        if ($value -lt 0) { throw 'シークレットキーに Base32 でない文字があります' }
        # 使い終えた上位のビットは捨てる(残すのは最大 7 ビット)
        $buffer = (($buffer -shl 5) -bor $value) -band 0xFFF
        $bits += 5
        if ($bits -ge 8) {
            $bits -= 8
            $bytes.Add([byte](($buffer -shr $bits) -band 0xFF))
        }
    }
    , $bytes.ToArray()
}

# Counter は「UNIX 時刻 ÷ 周期」の商
function Get-TotpCode([byte[]]$Key, [long]$Counter, [string]$Algorithm, [int]$Digits) {
    $message = [BitConverter]::GetBytes($Counter)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($message) }
    $hmac = switch ($Algorithm) {
        'SHA1' { [System.Security.Cryptography.HMACSHA1]::new($Key) }
        'SHA256' { [System.Security.Cryptography.HMACSHA256]::new($Key) }
        'SHA512' { [System.Security.Cryptography.HMACSHA512]::new($Key) }
        default { throw "対応していない TOTP の方式です: $Algorithm" }
    }
    try { $hash = $hmac.ComputeHash($message) } finally { $hmac.Dispose() }
    $offset = [int]$hash[$hash.Length - 1] -band 0x0F
    $binary = (([int]$hash[$offset] -band 0x7F) -shl 24) -bor ([int]$hash[$offset + 1] -shl 16) -bor ([int]$hash[$offset + 2] -shl 8) -bor [int]$hash[$offset + 3]
    ($binary % [int][Math]::Pow(10, $Digits)).ToString().PadLeft($Digits, '0')
}

if ($Check) {
    $ErrorActionPreference = 'Stop'
    $ascii = [System.Text.Encoding]::ASCII
    # RFC 6238 の付録 B の検証値(8 桁・30 秒)．鍵は方式ごとに長さが違う
    $keys = @{
        SHA1   = $ascii.GetBytes('12345678901234567890')
        SHA256 = $ascii.GetBytes('12345678901234567890123456789012')
        SHA512 = $ascii.GetBytes('1234567890123456789012345678901234567890123456789012345678901234')
    }
    $vectors = @(
        @(59, '94287082', '46119246', '90693936'),
        @(1111111109, '07081804', '68084774', '25091201'),
        @(1234567890, '89005924', '91819424', '93441116'),
        @(2000000000, '69279037', '90698825', '38618901'),
        @(20000000000, '65353130', '77737706', '47863826')
    )
    foreach ($vector in $vectors) {
        $counter = [long][Math]::Floor([long]$vector[0] / 30)
        $index = 1
        foreach ($algorithm in 'SHA1', 'SHA256', 'SHA512') {
            $actual = Get-TotpCode $keys[$algorithm] $counter $algorithm 8
            if ($actual -ne $vector[$index]) { throw "TOTP の値が違います: 時刻 $($vector[0]) $algorithm は $($vector[$index]) のはずが $actual" }
            $index += 1
        }
    }
    # Base32 と URI の読み取り．シークレットキーは RFC の SHA1 の鍵を Base32 にしたもの
    $otp = ConvertFrom-OtpAuthUri 'otpauth://totp/Example:user%40example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&algorithm=SHA1&digits=8&period=30'
    $decoded = ConvertFrom-Base32 $otp.Secret
    if ($ascii.GetString($decoded) -ne '12345678901234567890') { throw 'Base32 の読み取りが違います' }
    if ((Get-TotpCode $decoded 1 $otp.Algorithm $otp.Digits) -ne '94287082') { throw 'URI から読んだ設定での TOTP の値が違います' }
    $default = ConvertFrom-OtpAuthUri 'otpauth://totp/x?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
    if ($default.Algorithm -ne 'SHA1' -or $default.Digits -ne 6 -or $default.Period -ne 30) { throw 'URI の省いた項目の既定が違います' }
    Write-Host 'ok: TOTP の計算は RFC 6238 の検証値と合っています'
}
