# 配布物を作る

macOS の配布物は `.pkg` です．Zenzai のモデルを入れた本番のアプリを `/Library/Input Methods` に入れます．

```sh
make package-macos
```

`apps/macos/build/dist/s90.tokyo-IME-<版>.pkg` ができます．版は `apps/macos/project.yml` の `MARKETING_VERSION` です．

## 署名と公証

ほかの Mac で警告なしに開けるようにするには，アプリと `.pkg` の両方に Developer ID で署名し，Apple の公証を受けます．`tools/macos/package.sh` は，次のものがあれば自動で使います．

| 使うもの | 探し方 | 無いとき |
|---|---|---|
| アプリの署名 | `S90_APP_IDENTITY`，無ければ `make install-macos` と同じ決め方(入っている版を署名した証明書，無ければ Apple Development の最初の証明書) | アドホック署名．手元でしか動かない |
| .pkg の署名 | `S90_INSTALLER_IDENTITY`，無ければキーチェーンの Developer ID Installer | 署名しない．開くときに警告が出る |
| 公証 | `S90_NOTARY_PROFILE`(notarytool のキーチェーンのプロファイル名) | 公証しない．Gatekeeper に拒まれる |

公証のプロファイルは一度だけ作ります．

```sh
xcrun notarytool store-credentials s90-notary --apple-id <Apple ID> --team-id <チーム ID>
S90_NOTARY_PROFILE=s90-notary make package-macos
```

Developer ID の証明書で初めて署名するときは，キーチェーンへのアクセスを許すか聞かれます．「常に許可」を選ぶと次からは聞かれません．

## 署名の証明書を変えるとき

macOS はアプリのデータの置き場所(`~/Library/Containers/<バンドル ID>`)を，最初に作ったアプリの署名(チーム)に結び付けています．違うチームの証明書で署名した版を入れると，起動の途中(サンドボックスの準備)で止まり，入力できなくなります．2026-10-26 に，入っている本番(チーム E26F3E38B5)と違うチーム(YMFAF62K4Z)で署名した版を起動して，止まることを確かめました．

そのため `make install-macos` と `make package-macos` は，指定が無ければ入っている版を署名した証明書を使います．ほかの人に配るために Developer ID の証明書(`S90_APP_IDENTITY`)で署名した .pkg は，手元の Mac には入れないでください．

## 入れたあと

`.pkg` を開いて入れたあと，一度ログアウトしてログインし直し，システム設定 > キーボード > 入力ソース の「+」から「s90.tokyo IME」を足します．`.pkg` はログアウトを求める設定にしてあります．

2 回目からは `.pkg` で入れ直すだけで新しい版に替わります(入れたあとで古い版を止める)．
