// Windows の暗号の機能(CNG の BCrypt．OS の機能)で SHA-256 を求めるための薄い口．
// 起動のたびに確かめる同梱の辞書と Zenzai のモデル(合わせて 280MB ほど)のハッシュに使う．CPU の SHA の命令を使うので自前の実装より速い．
// Windows のほかでは何もせず，使えないと答える(NULL を返す)
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

#ifdef __cplusplus
}
#endif

#endif
