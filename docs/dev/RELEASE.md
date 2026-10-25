# 配布物を作る

macOS の配布物は `.pkg` です．Zenzai のモデルを入れた本番のアプリを `/Library/Input Methods` に入れます．

```sh
make package-macos
```

`apps/macos/build/dist/s90.tokyo-IME-<版>.pkg` ができます．版は `apps/macos/project.yml` の `MARKETING_VERSION` です．

## 署名と公証

`.pkg` には 2 つの作り方があります．

- **手元に入れる .pkg**(`S90_NOTARY_PROFILE` が無いとき): アプリは `make install-macos` と同じ決め方の証明書で署名します(入っている版と同じチームの証明書．同じチームの証明書が無いときや，前の版のデータの置き場所だけが残っているときは作るのをやめる)．.pkg はキーチェーンに Developer ID Installer があれば署名します
- **ほかの人に配る .pkg**(`S90_NOTARY_PROFILE` があるとき): アプリを Developer ID Application で署名し，時刻印を付けて公証を受けます．.pkg も Developer ID Installer で署名します．Developer ID Application の証明書でなければ作るのをやめます

| 使うもの | 指定 | 指定が無いとき |
|---|---|---|
| アプリの署名 | `S90_APP_IDENTITY`(名前か SHA-1) | 手元に入れる .pkg は入っている版と同じチームの証明書．配る .pkg は Developer ID Application |
| .pkg の署名 | `S90_INSTALLER_IDENTITY` | キーチェーンの Developer ID Installer．無ければ署名しない(開くときに警告が出る) |
| 公証 | `S90_NOTARY_PROFILE`(notarytool のキーチェーンのプロファイル名) | 公証しない．ほかの Mac では Gatekeeper に拒まれる |

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
