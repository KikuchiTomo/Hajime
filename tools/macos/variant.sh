# install.sh と uninstall.sh で共有する，本番と開発版の名前．apps/macos/project.yml の configs と合わせる
# 全ユーザー共通の置き場所に入れる．配布物(.pkg)と azooKey と同じ場所で，手元で入力ソースとして選べることを確かめた場所
destination="/Library/Input Methods"

variant() {
  configuration=$1
  case "$configuration" in
    Release) app_name="s90.tokyo IME"; bundle_id="tokyo.s90.inputmethod.S90IME" ;;
    Debug) app_name="s90.tokyo IME Dev"; bundle_id="tokyo.s90.inputmethod.S90IME.dev" ;;
    *) echo "Release か Debug を指定してください" >&2; exit 1 ;;
  esac
}
