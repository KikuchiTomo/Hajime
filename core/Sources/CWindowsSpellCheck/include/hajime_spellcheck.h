// Windows のスペルチェッカー(ISpellChecker．Windows 8 以降の OS の機能)を Swift から呼ぶための薄い口．
// 英単語の綴りの補正(R-02)の英単語の辞書に使う．Windows のほかでは何もせず，使えないと答える
#ifndef HAJIME_SPELLCHECK_H
#define HAJIME_SPELLCHECK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// スペルチェッカーを開く(呼んだスレッドで COM を使う)．使えれば 0，使えなければ負の数
int32_t hajime_spell_open(const uint16_t *language);

/// word(UTF-16，length 文字)が英単語か．英単語なら 1，違えば 0，使えなければ負の数
int32_t hajime_spell_is_word(const uint16_t *word, int32_t length);

/// word の綴りの候補を，改行(\n)で区切って buffer(capacity 文字)に書く．書いた文字数を返す．使えなければ負の数
int32_t hajime_spell_suggestions(const uint16_t *word, int32_t length, uint16_t *buffer, int32_t capacity, int32_t maximum);

/// 開いたスペルチェッカーを閉じる
void hajime_spell_close(void);

#ifdef __cplusplus
}
#endif

#endif
