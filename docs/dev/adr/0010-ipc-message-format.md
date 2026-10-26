# 0010 Windows のプロセス間のメッセージは長さ付きの JSON にし，定義から両方の言語の型を作る

- 状態: 採用
- 日付: 2026-10-26
- 関係する要件: なし(ADR 0003 の続き)

## 背景

ADR 0003 で，Windows では TSF の DLL(Rust)・`s90-engine-host`(Swift)・候補ウィンドウ(Rust)を別のプロセスにし，名前付きパイプで通信すると決めた．
形式は「Protocol Buffers か，より軽い独自の形式か」を DLL の大きさを見て決めることにしていた(`protocol/README.md`)．
DLL は入力先のすべてのアプリに読み込まれるので，依存を小さくしたい．Swift と Rust で型を手で二重に書くと，片方だけ変えて食い違うおそれがある．

## 判断

- 1 つのメッセージは「4 バイトの長さ(リトルエンディアン)＋UTF-8 の JSON」にする．長さの上限は定義の `maximumMessageBytes`(256KiB)で，超えたら接続を切る
- メッセージの型は `protocol/schema.json` に書く．`tools/protocol/generate.py` が Swift(`core/Sources/S90IPC/Generated/`)と Rust(`apps/windows/crates/ipc/src/generated.rs`)の型を作る．生成物はコミットし，`make check` で定義と合っているかを確かめる
- 型の種類は構造体・文字列の列挙・種類を表すキーで分ける共用体の 3 つだけにする．JSON の形は serde の internally tagged と同じ
- 両方の言語で同じ見本(`protocol/fixtures/messages.json`)を読み，読み戻して同じ JSON になることをテストで確かめる
- Swift は Foundation の `JSONEncoder`，Rust は `serde` と `serde_json` を使う．どちらも版を固定する
- 生成した型の `description`(Swift)と `Debug`(Rust)は文字列の中身を出さない(`docs/dev/SECURITY-MODEL.md`)
- 要求には番号を付け，応答を組にする．DLL が時間切れで捨てた応答を読み飛ばせるようにするため

## 検討したほかの案

| 案 | 採らなかった理由 |
|---|---|
| Protocol Buffers(azooKey-Windows と同じ gRPC か prost) | Swift の側に swift-protobuf，Rust の側に prost とコード生成の道具(protoc)が要る．gRPC は DLL に tokio と HTTP/2 を持ち込む |
| 独自のバイナリ形式 | 読み書きのコードも両方の言語で生成することになり，生成の道具が大きくなる．1 キーあたりのメッセージは数百バイトで，JSON でも往復の時間は変換の時間に比べて小さい |
| Swift と Rust で型を手で書く | 片方だけ変えて食い違うのを防げない．見本のテストで気づけても，直す手間が 2 倍になる |

## 結果

型を足すときは `schema.json` を変えて `make protocol` を実行するだけで済む．生成の道具は Python の標準のライブラリだけで動く．
JSON なので，名前付きパイプの中身を調べるときに読みやすい(入力の中身を含むので，調べるのは開発の環境だけにする)．
代わりに，バイナリの形式より大きく，読み書きに少し時間がかかる．1 キーあたりの往復の時間は ADR 0003 のとおり計測して見張る．
