// Windows の暗号の機能(CNG の BCrypt．OS の機能)で SHA-256 を求めるための薄い口．
// 同梱の辞書とモデル(合わせて 480MB ほど)のハッシュに使う(初めての起動と，ファイルかアプリが変わったあとの起動．ADR 0017)．CPU の SHA の命令を使うので自前の実装より速い．
// 起動のときに確かめた結果を使い回すための，ファイルの属性(大きさ・更新日時・ファイル ID)を読む口も置く(ADR 0017)．
// Windows のほかでは何もせず，使えないと答える(NULL や負の数を返す)
#ifndef HAJIME_HASH_H
#define HAJIME_HASH_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// SHA-256 を求める途中の状態．中身は C の側だけが知る
typedef struct hajime_sha256 hajime_sha256;

/// 求め始める．使えなければ NULL
hajime_sha256 *hajime_sha256_begin(void);

/// bytes(count バイト)を足す．成功なら 0，失敗なら負の数．失敗したあとは hajime_sha256_discard で放す
int32_t hajime_sha256_update(hajime_sha256 *state, const uint8_t *bytes, size_t count);

/// 32 バイトの値を digest に書き，state を放す．成功なら 0，失敗なら負の数(どちらでも state は放す)
int32_t hajime_sha256_finish(hajime_sha256 *state, uint8_t *digest);

/// 求めるのをやめて state を放す
void hajime_sha256_discard(hajime_sha256 *state);

/// ファイルを前回と同じものか見分ける属性(ADR 0017)．中身は読まない
typedef struct hajime_file_stamp {
    uint64_t size;
    /// 更新日時(FILETIME．1601 年からの 100 ナノ秒)
    int64_t modified;
    /// ボリュームのシリアル番号とファイルのインデックス(合わせてファイル ID)
    uint64_t volume;
    uint64_t file;
} hajime_file_stamp;

/// path(UTF-16 の NUL で終わるパス)のふつうのファイルの属性を stamp に書く．成功なら 0，無い・ディレクトリなどなら負の数
int32_t hajime_file_stamp_of(const uint16_t *path, hajime_file_stamp *stamp);

/// hajime_directory_stamps が見つけたファイルを 1 つずつ受け取る．name は NUL で終わらない UTF-16 で，length はその文字数
typedef void (*hajime_file_stamp_visitor)(void *context, const uint16_t *name, uint32_t length, const hajime_file_stamp *stamp);

/// directory(UTF-16 の NUL で終わるパス)のすぐ下のふつうのファイルの属性を，visitor に 1 つずつ渡す．
/// ディレクトリと再解析ポイント(シンボリックリンクなど)は渡さない．ファイルごとに開くより速い(同梱の辞書は数千のファイルがある)．
/// 成功なら 0，開けない・読めないときは負の数
int32_t hajime_directory_stamps(const uint16_t *directory, void *context, hajime_file_stamp_visitor visitor);

#ifdef __cplusplus
}
#endif

#endif
