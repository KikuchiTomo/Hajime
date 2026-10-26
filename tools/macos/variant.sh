# install.sh・uninstall.sh・package.sh で共有する，本番と開発版の名前と，署名の証明書の決め方．
# 名前は apps/macos/project.yml の configs と合わせる(app_name はアプリの名前，display_name は入力メニューに出す名前 S90_DISPLAY_NAME)
# 全ユーザー共通の置き場所に入れる．配布物(.pkg)と azooKey と同じ場所で，手元で入力ソースとして選べることを確かめた場所
destination="/Library/Input Methods"

# 開発版は Dev の構成でビルドする(最適化は本番と同じ)．Debug の構成は画像の書き出し用の別のアプリで，ここでは入れない
variant() {
  case "$1" in
    Release) configuration=Release; app_name="s90.tokyo IME"; display_name="s90"; bundle_id="tokyo.s90.inputmethod.S90IME" ;;
    Dev) configuration=Dev; app_name="s90.tokyo IME Dev"; display_name="s90 Dev"; bundle_id="tokyo.s90.inputmethod.S90IME.develop" ;;
    *) echo "Release か Dev を指定してください" >&2; exit 1 ;;
  esac
}

# 下の関数は変数の名前に _vs_ を付け，呼び出し側の変数を上書きしないようにする(sh の関数の変数は外と共有されるため)

# 証明書の一覧．1 行に「SHA-1<タブ>名前」．引数は security find-identity の種類(codesigning か basic)
identities() {
  security find-identity -v -p "${1:-codesigning}" | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(.*\)"$/\1	\2/p'
}

code_signing_identities() {
  identities codesigning
}

# 証明書(SHA-1)の名前．見つからなければ空
identity_name() {
  identities basic | awk -F '\t' -v hash="$1" '$1 == hash { print $2; exit }'
}

# 証明書(SHA-1)のチーム ID．証明書の組織単位(OU)に入っている．名前の括弧の中はチーム ID ではない
identity_team() {
  _vs_name=$(identity_name "$1")
  security find-certificate -a -Z -p -c "$_vs_name" 2>/dev/null | awk -v hash="$1" '
    /^SHA-1 hash: / { keep = ($3 == hash) }
    keep { print }
  ' | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p'
}

# 前のバージョンが作ったデータの置き場所(コンテナ)．アプリを消してもここは残る
container_path() {
  printf '%s\n' "$HOME/Library/Containers/$bundle_id"
}

# 署名に使う証明書(SHA-1)を決める．install.sh と package.sh で同じ決め方にする．
# macOS はアプリのデータの置き場所(コンテナ)を最初に作ったアプリの署名(チーム)に結び付けていて，
# 違うチームの証明書で署名したバージョンを入れると，起動の途中で止まって入力できなくなる(2026-10-26 に確かめた)．
#   1. S90_SIGN_IDENTITY があればそれ(名前か SHA-1)
#   2. 入っているバージョンが証明書で署名されていれば，それと同じチームの証明書．キーチェーンに無ければ止める
#   3. 入っているバージョンが無いか証明書で署名されておらず，前のバージョンのデータの置き場所が残っていれば止める
#      (置き場所を作った署名が分からず，違うチームで入れると止まるため)
#   4. どちらも無ければ(初めて入れるとき)，Apple Development の最初の証明書
# 名前ではなく SHA-1 で返す．同じ名前の証明書が 2 つあるときに codesign が選べなくなるため．必ず $(...) の中で呼ぶ
signing_identity() {
  if [ -n "${S90_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$S90_SIGN_IDENTITY"
    return
  fi
  _vs_installed="$destination/$app_name.app"
  _vs_team=""
  if [ -d "$_vs_installed" ]; then
    _vs_team=$(codesign -dvv "$_vs_installed" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    if [ -n "$_vs_team" ] && [ "$_vs_team" != "not set" ]; then
      for _vs_hash in $(code_signing_identities | cut -f1); do
        if [ "$(identity_team "$_vs_hash")" = "$_vs_team" ]; then
          printf '%s\n' "$_vs_hash"
          return
        fi
      done
      echo "入っている「${app_name}」はチーム ${_vs_team} の証明書で署名されていますが，その証明書がキーチェーンにありません．" >&2
      echo "違うチームで署名すると起動の途中で止まるので，入れるのをやめます．チーム ${_vs_team} の証明書を S90_SIGN_IDENTITY で指定するか，" >&2
      echo "アプリを消して(make uninstall-macos か make uninstall-dev-macos)から，Finder でデータの置き場所 $(container_path) をゴミ箱に入れて入れ直してください" >&2
      return 1
    fi
  fi
  if [ -d "$_vs_installed" ] && [ -d "$(container_path)" ]; then
    # 証明書で署名されていないバージョンが入っていて，それが作った置き場所がある
    if [ "${_vs_team:-}" = "not set" ]; then
      echo "入っている「${app_name}」はアドホック署名で，そのデータの置き場所 $(container_path) があります．" >&2
    else
      echo "入っている「${app_name}」の署名が読めず，そのデータの置き場所 $(container_path) があります．" >&2
    fi
    echo "証明書で署名すると起動の途中で止まるおそれがあるので，入れるのをやめます．" >&2
    echo "アドホック署名のまま入れ直すなら S90_SIGN_IDENTITY=- を付けてください．証明書で署名したバージョンに替えるなら，" >&2
    echo "学習データと設定を消してよければ，先にアプリを消して(make uninstall-macos か make uninstall-dev-macos)から，" >&2
    echo "Finder でその置き場所をゴミ箱に入れて入れ直してください(アプリが動いたままだと置き場所を作り直すため)" >&2
    return 1
  fi
  if [ -d "$(container_path)" ]; then
    echo "前の「${app_name}」のデータの置き場所 $(container_path) が残っていて，それを作った署名が分かりません．" >&2
    echo "違うチームで署名すると起動の途中で止まるので，入れるのをやめます．前と同じ証明書を S90_SIGN_IDENTITY で指定するか" >&2
    echo "(前がアドホック署名なら S90_SIGN_IDENTITY=-)，学習データと設定を消してよければ Finder でその置き場所をゴミ箱に入れてから入れ直してください" >&2
    return 1
  fi
  code_signing_identities | awk -F '\t' '$2 ~ /^Apple Development/ { print $1; exit }'
}
