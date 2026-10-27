# 配布物を作る

macOS の配布物は `.pkg` です．Zenzai のモデルを入れた本番のアプリを `/Library/Input Methods` に入れます．

```sh
make package-macos
```

`apps/macos/build/dist/s90.tokyo-IME-<バージョン>.pkg` ができます．バージョンは `apps/macos/project.yml` の `MARKETING_VERSION` です．配るたびに `tools/release/bump_version.sh macos` で PATCH を上げ(MINOR を上げるときは `tools/release/bump_version.sh macos minor`)，`macos/v0.1.1` のようにタグを付けます．番号の決まりは [ADR 0008](adr/0008-versioning.md) にあります．

## 署名と公証

`.pkg` には 2 つの作り方があります．

- **手元に入れる .pkg**(`S90_NOTARY_PROFILE` が無いとき): アプリは `make install-macos` と同じ決め方の証明書で署名します(入っているバージョンと同じチームの証明書．同じチームの証明書が無いときや，前のバージョンのデータの置き場所だけが残っているときは作るのをやめる)．.pkg はキーチェーンに Developer ID Installer があれば署名します
- **ほかの人に配る .pkg**(`S90_NOTARY_PROFILE` があるとき): アプリを Developer ID Application で署名し，時刻印を付けて公証を受けます．.pkg も Developer ID Installer で署名します．Developer ID Application の証明書でなければ作るのをやめます

| 使うもの | 指定 | 指定が無いとき |
|---|---|---|
| アプリの署名 | `S90_APP_IDENTITY`(名前か SHA-1) | 手元に入れる .pkg は入っているバージョンと同じチームの証明書．配る .pkg は Developer ID Application |
| .pkg の署名 | `S90_INSTALLER_IDENTITY` | キーチェーンの Developer ID Installer．無ければ署名しない(開くときに警告が出る) |
| 公証 | `S90_NOTARY_PROFILE`(notarytool のキーチェーンのプロファイル名) | 公証しない．ほかの Mac では Gatekeeper に拒まれる |

公証のプロファイルは一度だけ作ります．

```sh
xcrun notarytool store-credentials s90-notary --apple-id <Apple ID> --team-id <チーム ID>
S90_NOTARY_PROFILE=s90-notary make package-macos
```

Developer ID の証明書で初めて署名するときは，キーチェーンへのアクセスを許すか聞かれます．「常に許可」を選ぶと次からは聞かれません．

## 署名の証明書を変えるとき

macOS はアプリのデータの置き場所(`~/Library/Containers/<バンドル ID>`)を，最初に作ったアプリの署名(チーム)に結び付けています．違うチームの証明書で署名したバージョンを入れると，起動の途中(サンドボックスの準備)で止まり，入力できなくなります．2026-10-26 に，入っている本番(チーム E26F3E38B5)と違うチーム(YMFAF62K4Z)で署名したバージョンを起動して，止まることを確かめました．

そのため `make install-macos` と `make package-macos` は，指定が無ければ入っているバージョンを署名した証明書を使います．ほかの人に配るために Developer ID の証明書(`S90_APP_IDENTITY`)で署名した .pkg は，手元の Mac には入れないでください．

## 入れたあと

`.pkg` を開いて入れたあと，一度ログアウトしてログインし直し，システム設定 > キーボード > 入力ソース の「+」から「s90.tokyo IME」を足します．`.pkg` はログアウトを求める設定にしてあります．

2 回目からは `.pkg` で入れ直すだけで新しいバージョンに替わります(入れたあとで古いバージョンを止める)．

## GitHub の Releases に置く

配布物は GitHub Actions の `Release`(`.github/workflows/release.yml`)が作って Releases に置きます．どの経路で配るかは [ADR 0011](adr/0011-distribution.md) にあります．

1. `tools/release/bump_version.sh macos`(Windows は `windows`．MINOR を上げるときは後ろに `minor`)でバージョンを上げ，PR にしてマージします
2. main のマージしたコミットにタグを付けて push します

```sh
git tag macos/v0.1.1 origin/main
git push origin macos/v0.1.1
```

`Release` は，タグのバージョンがリポジトリに書いたバージョン(`tools/release/version.sh`)と同じかを確かめてから，その OS の配布物を作ります．Releases には配布物と，その SHA-256 の一覧(`SHA256SUMS.txt`)を置きます．タイトルは `v0.1.1-macos`・`v0.1.1-windows` のように，バージョンと OS を並べます．説明は `tools/release/notes/<OS>.md` に，同じ OS の前のタグからの変更の一覧を足したものです．1.0.0 より前のバージョンは試用のバージョン(pre-release)として置きます．

タグを付けたあとで作り直すときは，`gh workflow run release.yml -f tag=macos/v0.1.1` で動かします(同じタグの Release があれば失敗するので，先に消します)．

Secrets を入れるまでは，macOS の .pkg はアドホック署名で公証もしていないので，開くときに「このまま開く」が要ります．アドホック署名のアプリにはハードンドランタイムを付けません(付けるとチームの無い署名では同梱の llama.framework を読み込めず，起動の途中で止まる)．`tools/macos/package.sh` は，ハードンドランタイムが付いていてチームの無いアプリを作ったら止まります．Windows の .msi も署名していないので SmartScreen の警告が出ます．署名に使う証明書と公証の資格情報は GitHub の Secrets に置く必要があり，利用者が設定します．

## Releases の .pkg に署名して公証する

GitHub の Secrets に Developer ID の証明書と公証の資格情報を入れると，`Release` の macOS の .pkg を署名して公証します．入れていなければ，アドホック署名で作ります．Developer ID は手元の Apple Development の証明書と同じチームなので，署名した .pkg は開発に使っている Mac にもそのまま入れられます．

Secrets はリポジトリの管理者が入れます．値は `tools/macos/ci_signing.sh` が使い捨てのキーチェーンに入れて使い，仕事が終わると消します．記録には出しません．

1. Developer ID の証明書を 2 つ作る．Xcode の「設定 → Accounts → Manage Certificates → +」で「Developer ID Application」と「Developer ID Installer」を足す(作れるのはアカウントの持ち主だけ)
2. キーチェーンアクセスの「自分の証明書」で 2 つの証明書を選び，「書き出す」で 1 つの .p12 にする(パスワードを付ける)
3. App Store Connect の「ユーザとアクセス → 統合 → App Store Connect API」で，役割が Developer のチームのキーを作り，.p8 をダウンロードする(1 回しかダウンロードできない)．Key ID と Issuer ID を控える
4. GitHub のリポジトリの「Settings → Secrets and variables → Actions」に次の 5 つを入れる

| Secret | 中身 |
|---|---|
| `MACOS_CERTIFICATES_P12` | 2. の .p12 を base64 にしたもの(`base64 -i 証明書.p12 \| pbcopy`) |
| `MACOS_CERTIFICATES_PASSWORD` | 2. で付けたパスワード |
| `MACOS_NOTARY_KEY` | 3. の .p8 の中身(`pbcopy < AuthKey_XXXX.p8`) |
| `MACOS_NOTARY_KEY_ID` | 3. の Key ID |
| `MACOS_NOTARY_ISSUER_ID` | 3. の Issuer ID |

入れたら，`gh workflow run package-macos.yml` で作って，署名と公証が通るかを確かめます．公証した .pkg は，Gatekeeper の検査(`spctl --assess --type install`)を通ることを `package.sh` が確かめます．

## ワークフロー

| ファイル | 名前 | 仕事 | 動くとき |
|---|---|---|---|
| `ci.yml` | CI | `lint`・`core-macos`・`app-macos` | PR と main への push |
| `ci-windows.yml` | CI Windows | `rust-windows`・`core-windows` | Windows に関わるファイルを変えた PR と main への push |
| `ci-linux.yml` | CI Linux | `core-linux`(Zenzai なし．ADR 0012 の準備) | 手で動かす |
| `pr-title.yml` | PR title | `pr-title` | PR を開いた・直したとき |
| `package-macos.yml` | Package macOS | `package-macos` | `release.yml` から呼ぶ．手でも動かせる |
| `package-windows.yml` | Package Windows | `package-windows` | `release.yml` から呼ぶ．手でも動かせる |
| `release.yml` | Release | `prepare`・`package-macos`・`package-windows`・`publish` | タグ `macos/v*`・`windows/v*` を push したとき |

ファイルの名前は目的(ci・package・release)と OS で付け，仕事の名前は「何を-どこで」にそろえます．必須の検査(ルールセット)は仕事の名前で指定します．
