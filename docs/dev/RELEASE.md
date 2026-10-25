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
| アプリの署名 | `S90_APP_IDENTITY`，無ければキーチェーンの Developer ID Application，それも無ければ Apple Development | アドホック署名．手元でしか動かない |
| .pkg の署名 | `S90_INSTALLER_IDENTITY`，無ければキーチェーンの Developer ID Installer | 署名しない．開くときに警告が出る |
| 公証 | `S90_NOTARY_PROFILE`(notarytool のキーチェーンのプロファイル名) | 公証しない．Gatekeeper に拒まれる |

公証のプロファイルは一度だけ作ります．

```sh
xcrun notarytool store-credentials s90-notary --apple-id <Apple ID> --team-id <チーム ID>
S90_NOTARY_PROFILE=s90-notary make package-macos
```

Developer ID の証明書で初めて署名するときは，キーチェーンへのアクセスを許すか聞かれます．「常に許可」を選ぶと次からは聞かれません．

## 入れたあと

`.pkg` を開いて入れたあと，一度ログアウトしてログインし直し，システム設定 > キーボード > 入力ソース の「+」から「s90.tokyo IME」を足します．`.pkg` はログアウトを求める設定にしてあります．

2 回目からは `.pkg` で入れ直すだけで新しい版に替わります(入れたあとで古い版を止める)．
