# install.sh と uninstall.sh で共有する，本番と開発版の名前．apps/macos/project.yml の configs と合わせる
destination="$HOME/Library/Input Methods"

variant() {
  configuration=$1
  case "$configuration" in
    Release) app_name="s90.tokyo IME"; bundle_id="tokyo.s90.inputmethod.S90IME" ;;
    Debug) app_name="s90.tokyo IME Dev"; bundle_id="tokyo.s90.inputmethod.S90IME.dev" ;;
    *) echo "Release か Debug を指定してください" >&2; exit 1 ;;
  esac
}
