# install.sh と uninstall.sh で共有する，本番と開発版の名前．apps/macos/project.yml の configs と合わせる
# 全ユーザー共通の置き場所に入れる．配布物(.pkg)と azooKey と同じ場所で，手元で入力ソースとして選べることを確かめた場所
destination="/Library/Input Methods"

# 開発版は Dev の構成でビルドする．Debug の構成は最適化が無く，エンジンと Zenzai が遅すぎて入力できないため
variant() {
  case "$1" in
    Release) configuration=Release; app_name="s90.tokyo IME"; bundle_id="tokyo.s90.inputmethod.S90IME" ;;
    Debug|Dev) configuration=Dev; app_name="s90.tokyo IME Dev"; bundle_id="tokyo.s90.inputmethod.S90IME.develop" ;;
    *) echo "Release か Dev を指定してください" >&2; exit 1 ;;
  esac
}

# 署名に使う証明書を決める．install.sh と package.sh で同じ決め方にする．
# macOS はアプリのデータの置き場所(コンテナ)を最初に作ったアプリの署名(チーム)に結び付けていて，
# 違うチームの証明書で署名した版を入れると，起動の途中で止まって入力できなくなる(2026-10-26 に確かめた)．
# そのため，すでに入っている版があれば，それを署名した証明書を使う．
#   1. S90_SIGN_IDENTITY があればそれ
#   2. 入っている版を署名した証明書(キーチェーンにあれば)
#   3. Apple Development の最初の証明書
signing_identity() {
  if [ -n "${S90_SIGN_IDENTITY:-}" ]; then
    echo "$S90_SIGN_IDENTITY"
    return
  fi
  installed="$destination/$app_name.app"
  if [ -d "$installed" ]; then
    current=$(codesign -dvv "$installed" 2>&1 | awk -F '=' '/^Authority=/ { print $2; exit }')
    if [ -n "$current" ] && security find-identity -v -p codesigning | grep -qF "\"$current\""; then
      echo "$current"
      return
    fi
  fi
  security find-identity -v -p codesigning | awk -F '"' '/Apple Development/ { print $2; exit }'
}
