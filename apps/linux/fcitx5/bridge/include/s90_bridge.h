/* Fcitx 5 のアドオンから呼ぶ橋渡し(Rust の s90-fcitx5-bridge)の関数．
 * 文字列はすべて UTF-8．橋渡しが返す文字列は，次に同じ橋渡しの関数を呼ぶまで有効．
 * どの関数も 1 本のスレッド(Fcitx 5 の事象の輪)から呼ぶ */
#ifndef S90_BRIDGE_H
#define S90_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct S90Bridge S90Bridge;

/* キーの種類．Rust の ffi.rs と同じ順 */
enum S90KeyKind {
    S90_KEY_CHARACTER = 0,
    S90_KEY_SPACE,
    S90_KEY_ENTER,
    S90_KEY_BACKSPACE,
    S90_KEY_DELETE,
    S90_KEY_ESCAPE,
    S90_KEY_TAB,
    S90_KEY_UP,
    S90_KEY_DOWN,
    S90_KEY_LEFT,
    S90_KEY_RIGHT,
    S90_KEY_HOME,
    S90_KEY_END,
    S90_KEY_PAGE_UP,
    S90_KEY_PAGE_DOWN,
    S90_KEY_EISU,
    S90_KEY_KANA,
    S90_KEY_YEN,
    S90_KEY_FUNCTION,
    S90_KEY_HANKAKU_ZENKAKU,
    S90_KEY_HENKAN,
    S90_KEY_MUHENKAN,
};

enum S90Modifier {
    S90_MODIFIER_SHIFT = 1,
    S90_MODIFIER_CONTROL = 2,
    S90_MODIFIER_ALT = 4,
};

/* 入力中の文字の見た目 */
enum S90Style {
    S90_STYLE_READING = 0,
    S90_STYLE_CONVERTED,
    S90_STYLE_FOCUSED,
    S90_STYLE_CORRECTION,
};

/* engine_path はエンジンの実行ファイル(NULL なら起こさない)．つなげなくても作れる(あとでつなぐ)．失敗すれば NULL */
S90Bridge *s90_bridge_new(const char *engine_path);
void s90_bridge_free(S90Bridge *bridge);

/* 候補の一覧が変わると読めるようになる記述子．読めたら s90_bridge_load_panel を呼ぶ */
int s90_bridge_notify_fd(S90Bridge *bridge);

/* キーを送る．受け取ったら 1(アプリに渡さない)．text は S90_KEY_CHARACTER のときの文字，number は S90_KEY_FUNCTION の番号 */
int s90_bridge_key(S90Bridge *bridge, uint32_t kind, const char *text, uint32_t number, uint32_t modifiers, int keypad,
                   const char *application_id, int secure);
/* s90_bridge_wake_after の時間が過ぎたら呼ぶ(裏で求めた訂正などを受け取る) */
void s90_bridge_wake(S90Bridge *bridge, const char *application_id, int secure);
/* 入力先から外れた */
void s90_bridge_deactivate(S90Bridge *bridge);

/* 直前の key・wake・deactivate の結果 */
const char *s90_bridge_commit(S90Bridge *bridge);
size_t s90_bridge_preedit_count(S90Bridge *bridge);
const char *s90_bridge_preedit_text(S90Bridge *bridge, size_t index, uint32_t *style);
int s90_bridge_is_composing(S90Bridge *bridge);
/* 0 なら wake は要らない(ミリ秒) */
uint32_t s90_bridge_wake_after(S90Bridge *bridge);

/* 候補の一覧を取り込む．以下の関数は取り込んだ一覧を返す */
void s90_bridge_load_panel(S90Bridge *bridge);
size_t s90_bridge_candidate_count(S90Bridge *bridge);
const char *s90_bridge_candidate(S90Bridge *bridge, size_t index);
/* 選んでいる候補の位置．無ければ -1 */
int32_t s90_bridge_selected(S90Bridge *bridge);
const char *s90_bridge_note(S90Bridge *bridge);
const char *s90_bridge_hints(S90Bridge *bridge);

#ifdef __cplusplus
}
#endif

#endif
