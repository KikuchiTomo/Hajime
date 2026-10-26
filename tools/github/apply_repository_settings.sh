#!/bin/sh
# GitHub のリポジトリの設定を当てる．何度実行しても同じ状態になる．
# 決まりの説明は docs/dev/REPOSITORY.md．設定を変えるときは，このファイルと文書を一緒に変える．
#
# 使い方: tools/github/apply_repository_settings.sh [owner/repo]
# 必要なもの: gh(リポジトリの管理者の権限でログインしていること)
set -eu
repo=${1:-KikuchiTomo/s90.tokyo-IME}

echo "== マージの方式: スカッシュマージだけを許す"
# PR のタイトルがそのまま main のコミットの 1 行になる．本文は付けない(コミットは 1 行の決まり)
gh api -X PATCH "repos/$repo" --silent \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F allow_auto_merge=true \
  -F allow_update_branch=true \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=BLANK \
  -F has_wiki=false \
  -F has_projects=false \
  -F has_discussions=false

echo "== セキュリティの機能"
gh api -X PUT "repos/$repo/vulnerability-alerts" --silent
gh api -X PUT "repos/$repo/automated-security-fixes" --silent
gh api -X PUT "repos/$repo/private-vulnerability-reporting" --silent
gh api -X PATCH "repos/$repo" --silent --input - <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
JSON

echo "== main を守るルール"
ruleset_name="main を守る"
ruleset=$(cat <<'JSON'
{
  "name": "main を守る",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "lint" },
          { "context": "core-macos" },
          { "context": "app-macos" },
          { "context": "pr-title" }
        ]
      }
    }
  ]
}
JSON
)
existing=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$ruleset_name\") | .id")
if [ -n "$existing" ]; then
  echo "$ruleset" | gh api -X PUT "repos/$repo/rulesets/$existing" --silent --input -
else
  echo "$ruleset" | gh api -X POST "repos/$repo/rulesets" --silent --input -
fi

echo "== ラベル"
label() { gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force >/dev/null; }
# 種類(Conventional Commits の type に対応)
label "type: feat" "1d76db" "機能の追加"
label "type: fix" "d73a4a" "不具合の修正"
label "type: docs" "0075ca" "文書"
label "type: refactor" "c5def5" "振る舞いを変えない整理"
label "type: test" "bfd4f2" "テスト"
label "type: ci" "000000" "CI とリポジトリの設定"
label "type: chore" "ededed" "その他の雑務"
# 範囲(コミットのスコープに対応)
label "scope: core" "5319e7" "core(入力の処理)"
label "scope: macos" "5319e7" "macOS のアプリ"
label "scope: windows" "5319e7" "Windows のアプリ"
label "scope: design" "f9d0c4" "見た目とデザイントークン"
label "scope: skills" "5319e7" "Claude Code のスキル"
# 状態
label "security" "b60205" "セキュリティとプライバシー"
label "needs: decision" "fbca04" "判断(ADR)が要る"
label "dependencies" "0366d6" "依存の更新"
label "github_actions" "000000" "GitHub Actions の更新"
label "swift" "f05138" "Swift のパッケージの更新"

echo "設定しました: $repo"
