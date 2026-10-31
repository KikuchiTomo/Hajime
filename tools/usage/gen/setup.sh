#!/usr/bin/env bash
# Setup for ime-usage-gen (macOS / Linux). Safe to run more than once.
#   1. checks Ruby
#   2. checks / installs Claude Code (the `claude` command)
#   3. checks that `claude -p` can actually call a model (login)
#   4. downloads Mozc dictionary_oss + japanese-usage-dictionary into data/
set -u
cd "$(dirname "$0")"

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
ng()   { printf "  \033[31m✗\033[0m %s\n" "$*"; }
info() { printf "\n\033[1m%s\033[0m\n" "$*"; }

# ---------------------------------------------------------------- Ruby
info "1. Ruby"
if command -v ruby >/dev/null 2>&1 && ruby -e 'exit(RUBY_VERSION >= "3.0" ? 0 : 1)'; then
  ok "ruby $(ruby -e 'print RUBY_VERSION') ($(command -v ruby))"
else
  ng "Ruby 3.0 以上が必要です（rbenv なら: rbenv install 3.3.6 && rbenv local 3.3.6）"
  exit 1
fi

# ---------------------------------------------------------------- Claude Code
info "2. Claude Code"
if ! command -v claude >/dev/null 2>&1 && [ -x "$HOME/.local/bin/claude" ]; then
  export PATH="$HOME/.local/bin:$PATH"
  echo "  (~/.local/bin を PATH に追加してください: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc)"
fi
if command -v claude >/dev/null 2>&1; then
  ok "$(claude --version 2>/dev/null) ($(command -v claude))"
else
  ng "claude コマンドが見つかりません"
  printf "  公式インストーラ (curl -fsSL https://claude.ai/install.sh | bash) を実行しますか? [y/N] "
  read -r ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
    command -v claude >/dev/null 2>&1 || { ng "インストール後も claude が見つかりません。新しいターミナルで再実行してください"; exit 1; }
    ok "$(claude --version)"
  else
    echo "  Homebrew なら: brew install --cask claude-code"
    exit 1
  fi
fi

# ---------------------------------------------------------------- Login check
info "3. claude -p の動作確認（Haiku に1回だけ問い合わせます）"
tmp=$(mktemp -d)
bare=""
[ "${CLAUDE_BARE:-0}" = "1" ] && bare="--bare"
settings="{}"
[ -n "${CLAUDE_API_KEY_HELPER:-}" ] && settings=$(ruby -rjson -e 'print JSON.generate("apiKeyHelper" => ENV["CLAUDE_API_KEY_HELPER"])')
out=$(cd "$tmp" && echo '「OK」とだけ答えて' | claude $bare -p --settings "$settings" --model haiku --output-format json \
        --tools "" --strict-mcp-config --disable-slash-commands --no-session-persistence 2>&1)
rmdir "$tmp" 2>/dev/null
if echo "$out" | ruby -rjson -e 'd=JSON.parse(STDIN.read) rescue exit(1); exit(d["is_error"] ? 1 : 0)'; then
  ok "claude -p OK"
else
  ng "claude -p が失敗しました:"
  echo "$out" | head -5 | sed 's/^/    /'
  cat <<'EOS'

  ログインが必要です。次のどちらかを行ってから、もう一度 ./setup.sh を実行してください。
    a) サブスクリプション（Pro / Max など）: ターミナルで `claude` を起動し、
       ブラウザでログイン → `/exit` で終了
    b) API キー: export ANTHROPIC_API_KEY=sk-ant-...
       （CLAUDE_BARE=1 も付けると、~/.claude のフックやプラグインを読み込まずに動きます）
    c) 1Password などに保存したキー: キーを出力するコマンドを CLAUDE_API_KEY_HELPER に設定
       例: export CLAUDE_API_KEY_HELPER="op read op://Personal/ANTHROPIC_API_KEY/credential"
EOS
  exit 1
fi

# ---------------------------------------------------------------- Data
info "4. 辞書データ (data/)"
mkdir -p data
MOZC=https://raw.githubusercontent.com/google/mozc/master/src/data/dictionary_oss
USAGE=https://raw.githubusercontent.com/hiroyuki-komatsu/japanese-usage-dictionary/master
fetch() { # url dest
  if [ -s "$2" ]; then ok "$2 (既存)"; return; fi
  if curl -fsSL -o "$2" "$1"; then ok "$2"; else ng "取得失敗: $1"; exit 1; fi
}
for i in 0 1 2 3 4 5 6 7 8 9; do fetch "$MOZC/dictionary0$i.txt" "data/dictionary0$i.txt"; done
fetch "$MOZC/id.def"     data/id.def
fetch "$MOZC/README.txt" data/MOZC_DICTIONARY_README.txt   # IPAdic / ICOT license text
# Inside the Hajime repository, use the bundled copy (pinned by tools/usage/update.sh).
if [ -s ../../../data/usage/usage_dict.txt ]; then
  cp ../../../data/usage/usage_dict.txt data/usage_dict.txt && ok "data/usage_dict.txt (data/usage から)"
else
  fetch "$USAGE/usage_dict.txt" data/usage_dict.txt
fi
fetch "$USAGE/LICENSE"        data/USAGE_DICT_LICENSE

info "準備完了。次は:"
cat <<'EOS'
  ruby extract_groups.rb          # 対象グループ抽出 → work/groups.jsonl
  ruby generate.rb --limit 50     # まずは50件だけ Haiku で生成
  ruby verify.rb                  # Sonnet で検証
  ruby build_tsv.rb               # → out/usage_dict_extra.tsv
EOS
