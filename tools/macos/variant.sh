# install.sh・uninstall.sh・package.sh で共有する，本番と開発版の名前と，署名の証明書の決め方．
# 名前は apps/macos/project.yml の configs と合わせる
# 全ユーザー共通の置き場所に入れる．配布物(.pkg)と azooKey と同じ場所で，手元で入力ソースとして選べることを確かめた場所
destination="/Library/Input Methods"

# 開発版は Dev の構成でビルドする(最適化は本番と同じ)．Debug の構成は画像の書き出し用の別のアプリで，ここでは入れない
variant() {
  case "$1" in
    Release) configuration=Release; app_name="s90.tokyo IME"; bundle_id="tokyo.s90.inputmethod.S90IME" ;;
    Dev) configuration=Dev; app_name="s90.tokyo IME Dev"; bundle_id="tokyo.s90.inputmethod.S90IME.develop" ;;
    *) echo "Release か Dev を指定してください" >&2; exit 1 ;;
  esac
}

# コード署名に使える証明書の一覧．1 行に「SHA-1<タブ>名前」
code_signing_identities() {
  security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(.*\)"$/\1	\2/p'
}

# 証明書(SHA-1)の名前
identity_name() {
  code_signing_identities | awk -F '\t' -v hash="$1" '$1 == hash { print $2; exit }'
}

# 証明書(SHA-1)のチーム ID．証明書の組織単位(OU)に入っている．名前の括弧の中はチーム ID ではない
identity_team() {
  name=$(identity_name "$1")
  security find-certificate -a -Z -p -c "$name" 2>/dev/null | awk -v hash="$1" '
    /^SHA-1 hash: / { keep = ($3 == hash) }
    keep { print }
  ' | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p'
}

# 署名に使う証明書(SHA-1)を決める．install.sh と package.sh で同じ決め方にする．
# macOS はアプリのデータの置き場所(コンテナ)を最初に作ったアプリの署名(チーム)に結び付けていて，
# 違うチームの証明書で署名した版を入れると，起動の途中で止まって入力できなくなる(2026-10-26 に確かめた)．
#   1. S90_SIGN_IDENTITY があればそれ(名前か SHA-1)
#   2. 入っている版があれば，それと同じチームの証明書．キーチェーンに無ければ止める(止まる版を入れないため)
#   3. 入っている版が無いか，証明書で署名されていなければ，Apple Development の最初の証明書
# 名前ではなく SHA-1 で返す．同じ名前の証明書が 2 つあるときに codesign が選べなくなるため
signing_identity() {
  if [ -n "${S90_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$S90_SIGN_IDENTITY"
    return
  fi
  installed="$destination/$app_name.app"
  if [ -d "$installed" ]; then
    team=$(codesign -dvv "$installed" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    if [ -n "$team" ] && [ "$team" != "not set" ]; then
      for hash in $(code_signing_identities | cut -f1); do
        if [ "$(identity_team "$hash")" = "$team" ]; then
          printf '%s\n' "$hash"
          return
        fi
      done
      echo "入っている「${app_name}」はチーム ${team} の証明書で署名されていますが，その証明書がキーチェーンにありません．" >&2
      echo "違うチームで署名すると起動の途中で止まるので，入れるのをやめます．S90_SIGN_IDENTITY で証明書を指定してください" >&2
      return 1
    fi
    echo "入っている「${app_name}」は証明書で署名されていないので，Apple Development の最初の証明書を使います" >&2
  fi
  code_signing_identities | awk -F '\t' '$2 ~ /^Apple Development/ { print $1; exit }'
}
