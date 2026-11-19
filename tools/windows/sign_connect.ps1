# 署名に使う証明書を，この PC の証明書ストア(CurrentUser\My)から使えるようにする．終わったら拇印を環境変数 HAJIME_SIGN_THUMBPRINT に入れる．
# 署名は tools/windows/sign.ps1，後始末は tools/windows/sign_disconnect.ps1．
#
# certum: Certum の「Open Source Code Signing in the Cloud」の証明書．鍵は Certum のクラウド(SimplySign)にあり，
#         Certum の SimplySign Desktop にワンタイムコードでログインしているあいだだけ使える．
#         Certum は CI からのログインの方法を案内していないので，SimplySign Desktop の /autologin を使い，だめならログインの窓に入力する．
#         SimplySign Desktop の更新で通らなくなったら，下のバージョンとハッシュ，ログインの手順を見直す．
#         資格情報は環境変数で渡す(GitHub の Secrets)．どれも表示しない
#           CERTUM_EMAIL       SimplySign のアカウントのメールアドレス
#           CERTUM_OTPAUTH     SimplySign のアプリを登録するときの QR コードの中身(otpauth://totp/... の全体)
#           CERTUM_THUMBPRINT  使う証明書の拇印(SHA-1)．省くと，アカウントにただ 1 つある Certum のコード署名の証明書を使う
# test:   使い捨ての自己署名の証明書を作り，この PC でだけ信頼する．署名の手順を証明書なしで確かめるためのもので，CI でしか動かさない
#
# 使い方: tools/windows/sign_connect.ps1 -Provider certum
#         tools/windows/sign_connect.ps1 -Provider certum -InstallOnly   SimplySign Desktop を入れて確かめるところまで(ログインしない)
#         tools/windows/sign_connect.ps1 -Provider test
param(
    [Parameter(Mandatory = $true)][ValidateSet('certum', 'test')][string]$Provider,
    [switch]$InstallOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sign_totp.ps1')

# SimplySign Desktop(Certum が配布するインストーラー)．バージョンを上げるときは，ハッシュも合わせて直す
$simplySignVersion = '9.4.3.90'
$simplySignUrl = "https://files.certum.eu/software/SimplySignDesktop/Windows/$simplySignVersion/SimplySignDesktop-$simplySignVersion-64-bit-en.msi"
$simplySignSha256 = 'ce2b38ef0124a574bc08e5558726099caac79a7c58b8d3d712f629371fe1bcb7'
# インストーラーの署名の発行先(Certum を運営する会社)
$simplySignPublisher = 'Asseco Data Systems'
$simplySignExe = Join-Path $env:ProgramFiles 'Certum\SimplySign Desktop\SimplySignDesktop.exe'
$simplySignSettings = 'HKCU:\Software\Certum\SimplySign'
$testSubject = 'CN=Hajime IME signing test'
$codeSigningUsage = '1.3.6.1.5.5.7.3.3'
# ログインしてから証明書がストアに現れるまで待つ秒数
$certificateWaitSeconds = 45

function Publish-Thumbprint([string]$Thumbprint) {
    if ($env:GITHUB_ENV) {
        "HAJIME_SIGN_THUMBPRINT=$Thumbprint" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
    }
    $env:HAJIME_SIGN_THUMBPRINT = $Thumbprint
}

function Install-SimplySign {
    if (-not (Test-Path -LiteralPath $simplySignExe)) {
        $temporary = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
        $installer = Join-Path $temporary "SimplySignDesktop-$simplySignVersion.msi"
        for ($attempt = 1; ; $attempt++) {
            try {
                Invoke-WebRequest -Uri $simplySignUrl -OutFile $installer -TimeoutSec 180
                break
            } catch {
                if ($attempt -ge 3) { throw }
                Write-Host "SimplySign Desktop を取得できませんでした($attempt 回目)．やり直します"
                Start-Sleep -Seconds (5 * $attempt)
            }
        }
        # 動かす前に，決めたバージョンのファイルであることと，Certum の署名があることの両方を確かめる
        $actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $simplySignSha256) { throw "SimplySign Desktop の SHA-256 が一致しません: $actual" }
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        $signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { '' }
        if ($signature.Status -ne 'Valid' -or $signer -notmatch [Regex]::Escape($simplySignPublisher)) {
            throw "SimplySign Desktop の署名を確かめられません: $($signature.Status) $signer"
        }
        Write-Host "SimplySign Desktop $simplySignVersion の署名: $signer"
        $process = Start-Process msiexec.exe -ArgumentList @('/i', "`"$installer`"", '/quiet', '/norestart') -PassThru -Wait
        # 3010 は「再起動すると完了」．使い捨ての PC なので成功として扱う
        if ($process.ExitCode -notin 0, 3010) { throw "SimplySign Desktop を入れられませんでした(msiexec の終了コード $($process.ExitCode))" }
        Remove-Item -LiteralPath $installer -Force
    }
    if (-not (Test-Path -LiteralPath $simplySignExe)) { throw "SimplySign Desktop がありません: $simplySignExe" }

    # 人のいない PC 向けの設定(資格情報は書かない)．
    # signtool が鍵を求めたときにログインの窓を出さない(セッションが切れたら，待ち続けずに失敗させる)．
    # 切ったら証明書をストアから外す．PIN はつないでいるあいだだけ覚える
    New-Item -Path $simplySignSettings -Force | Out-Null
    $settings = [ordered]@{
        ShowLoginDialogOnStart             = 0
        ShowLoginDialogOnAppRequest        = 0
        RememberLastUserName               = 0
        Autostart                          = 0
        UnregisterCertificatesOnDisconnect = 1
        RememberPINinCSP                   = 1
        ForgetPINinCSPonDisconnect         = 1
        LangID                             = 9
    }
    foreach ($name in $settings.Keys) {
        New-ItemProperty -Path $simplySignSettings -Name $name -Value $settings[$name] -PropertyType DWord -Force | Out-Null
    }
    Write-Host "ok: SimplySign Desktop $simplySignVersion を使えます"
}

# 今使えるコード署名の証明書を探す．拇印の指定があればそれだけを見る
function Find-CertumCertificate([string]$Expected) {
    $now = Get-Date
    $candidates = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object {
            $_.HasPrivateKey -and $_.NotBefore -le $now -and $_.NotAfter -gt $now -and
            ($_.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq $codeSigningUsage })
        })
    if ($Expected) { return @($candidates | Where-Object { $_.Thumbprint -eq $Expected }) | Select-Object -First 1 }
    $certum = @($candidates | Where-Object { $_.Issuer -match 'Certum' })
    if ($certum.Count -gt 1) { throw 'Certum のコード署名の証明書が複数あります．CERTUM_THUMBPRINT で使うものを指定してください' }
    $certum | Select-Object -First 1
}

function Wait-CertumCertificate([string]$Expected) {
    $deadline = (Get-Date).AddSeconds($certificateWaitSeconds)
    do {
        $certificate = Find-CertumCertificate $Expected
        if ($certificate) { return $certificate }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    $null
}

function Stop-SimplySign {
    Get-Process SimplySignDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# SendKeys が特別に扱う文字を，そのままの文字として送れるようにする
function ConvertTo-SendKeysText([string]$Text) {
    [Regex]::Replace($Text, '[+^%~(){}\[\]]', { param($match) '{' + $match.Value + '}' })
}

function Connect-Certum {
    $email = "$env:CERTUM_EMAIL".Trim()
    $uri = "$env:CERTUM_OTPAUTH".Trim()
    $expected = ("$env:CERTUM_THUMBPRINT" -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if (-not $email -or -not $uri) { throw 'CERTUM_EMAIL と CERTUM_OTPAUTH がありません．GitHub の Secrets に入れてください' }
    if ($expected -and $expected.Length -ne 40) { throw 'CERTUM_THUMBPRINT は 16 進の 40 文字(SHA-1)で指定してください' }
    $otp = ConvertFrom-OtpAuthUri $uri
    # Secrets に入っているのは URI の全体なので，中のシークレットキーは自分で伏せる
    Write-Host "::add-mask::$($otp.Secret)"
    $key = ConvertFrom-Base32 $otp.Secret

    # 前に試した周期のコードは使わない(Certum は断ったコードの周期での再試行を受け付けない)．
    # 送ってから確かめられるまで数秒かかるので，周期の残りが少ないときは次の周期を待つ
    $state = @{ LastCounter = [long]-1 }
    $nextCode = {
        while ($true) {
            $seconds = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $counter = [long][Math]::Floor($seconds / $otp.Period)
            $left = $otp.Period - ($seconds % $otp.Period)
            if ($counter -gt $state.LastCounter -and $left -ge 20) { break }
            Start-Sleep -Seconds ($left + 1)
        }
        $state.LastCounter = $counter
        $code = Get-TotpCode $key $counter $otp.Algorithm $otp.Digits
        Write-Host "::add-mask::$code"
        $code
    }

    $certificate = $null
    # 1) SimplySign Desktop 自身の無人のログイン
    for ($attempt = 1; $attempt -le 3 -and -not $certificate; $attempt++) {
        $code = & $nextCode
        Write-Host "SimplySign にログインします(/autologin，$attempt 回目)"
        Start-Process -FilePath $simplySignExe -ArgumentList @('/autologin', $email, $code) | Out-Null
        $certificate = Wait-CertumCertificate $expected
    }
    # 2) だめなら，ログインの窓にメールアドレスとコードを入力する
    if (-not $certificate) {
        Write-Host 'ログインの窓への入力に切り替えます'
        Stop-SimplySign
        New-ItemProperty -Path $simplySignSettings -Name ShowLoginDialogOnStart -Value 1 -PropertyType DWord -Force | Out-Null
        $shell = New-Object -ComObject WScript.Shell
        for ($attempt = 1; $attempt -le 2 -and -not $certificate; $attempt++) {
            Stop-SimplySign
            $process = Start-Process -FilePath $simplySignExe -PassThru
            $active = $false
            for ($second = 0; $second -lt 30 -and -not $active; $second++) {
                Start-Sleep -Seconds 1
                $active = $shell.AppActivate($process.Id)
            }
            if (-not $active) {
                Write-Host 'ログインの窓が見つかりません'
                continue
            }
            $code = & $nextCode
            [void]$shell.AppActivate($process.Id)
            Start-Sleep -Milliseconds 500
            $shell.SendKeys('^a{DEL}' + (ConvertTo-SendKeysText $email))
            Start-Sleep -Milliseconds 300
            $shell.SendKeys('{TAB}')
            Start-Sleep -Milliseconds 300
            $shell.SendKeys('^a{DEL}' + $code)
            Start-Sleep -Milliseconds 300
            $shell.SendKeys('{ENTER}')
            $certificate = Wait-CertumCertificate $expected
        }
    }
    if (-not $certificate) {
        throw 'SimplySign にログインできませんでした．CERTUM_EMAIL と CERTUM_OTPAUTH，証明書が有効かを確かめてください'
    }

    # 証明書の名前(持ち主の氏名)は出さない．公開リポジトリの記録は誰でも読める
    Write-Host "ok: Certum の証明書を使えます(発行者: $($certificate.Issuer)，期限: $($certificate.NotAfter.ToString('yyyy-MM-dd')))"
    Write-Host "拇印: $($certificate.Thumbprint)"
    if ($certificate.NotAfter -lt (Get-Date).AddDays(30)) {
        Write-Host "::warning::署名の証明書の期限が $($certificate.NotAfter.ToString('yyyy-MM-dd')) に切れます．Certum で更新してください"
    }
    Publish-Thumbprint $certificate.Thumbprint
}

function Connect-Test {
    # 証明書を信頼するルートに足すので，使い捨ての PC でしか動かさない
    if ($env:GITHUB_ACTIONS -ne 'true') { throw 'test の証明書は GitHub Actions のランナーでだけ作れます' }
    $certificate = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddDays(2)
    # 署名の検証が通るよう，公開の部分だけをこの PC の信頼するルートに足す(LocalMachine は確認の窓が出ない)
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('Root', 'LocalMachine')
    $store.Open('ReadWrite')
    try {
        $store.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificate.RawData))
    } finally {
        $store.Close()
    }
    Write-Host "ok: 使い捨ての証明書を作りました(拇印: $($certificate.Thumbprint))"
    Publish-Thumbprint $certificate.Thumbprint
}

if ($Provider -eq 'certum') {
    Install-SimplySign
    if (-not $InstallOnly) { Connect-Certum }
} else {
    Connect-Test
}
