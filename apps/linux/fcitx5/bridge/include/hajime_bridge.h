/* Fcitx 5 のアドオンから呼ぶ橋渡し(Rust の hajime-fcitx5-bridge)の関数．
 * 文字列はすべて UTF-8．橋渡しが返す文字列は，次に同じ橋渡しの関数を呼ぶまで有効．
 * どの関数も 1 本のスレッド(Fcitx 5 の事象の輪)から呼ぶ */
#ifndef HAJIME_BRIDGE_H
#define HAJIME_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HajimeBridge HajimeBridge;

/* キーの種類．Rust の ffi.rs と同じ順 */
enum HajimeKeyKind {
    HAJIME_KEY_CHARACTER = 0,
    HAJIME_KEY_SPACE,
    HAJIME_KEY_ENTER,
    HAJIME_KEY_BACKSPACE,
    HAJIME_KEY_DELETE,
    HAJIME_KEY_ESCAPE,
    HAJIME_KEY_TAB,
    HAJIME_KEY_UP,
    HAJIME_KEY_DOWN,
    HAJIME_KEY_LEFT,
    HAJIME_KEY_RIGHT,
    HAJIME_KEY_HOME,
    HAJIME_KEY_END,
    HAJIME_KEY_PAGE_UP,
    HAJIME_KEY_PAGE_DOWN,
    HAJIME_KEY_EISU,
    HAJIME_KEY_KANA,
    HAJIME_KEY_YEN,
    HAJIME_KEY_FUNCTION,
    HAJIME_KEY_HANKAKU_ZENKAKU,
    HAJIME_KEY_HENKAN,
    HAJIME_KEY_MUHENKAN,
};

enum HajimeModifier {
    HAJIME_MODIFIER_SHIFT = 1,
    HAJIME_MODIFIER_CONTROL = 2,
    HAJIME_MODIFIER_ALT = 4,
};

/* 入力中の文字の見た目 */
enum HajimeStyle {
    HAJIME_STYLE_READING = 0,
    HAJIME_STYLE_CONVERTED,
    HAJIME_STYLE_FOCUSED,
    HAJIME_STYLE_CORRECTION,
};

/* engine_path はエンジンの実行ファイル(NULL なら起こさない)．つなげなくても作れる(あとでつなぐ)．失敗すれば NULL */
HajimeBridge *hajime_bridge_new(const char *engine_path);
void hajime_bridge_free(HajimeBridge *bridge);

/* 候補の一覧が変わると読めるようになる記述子．読めたら hajime_bridge_load_panel を呼ぶ */
int hajime_bridge_notify_fd(HajimeBridge *bridge);

/* キーを送る．受け取ったら 1(アプリに渡さない)．text は HAJIME_KEY_CHARACTER のときの文字，number は HAJIME_KEY_FUNCTION の番号 */
int hajime_bridge_key(HajimeBridge *bridge, uint32_t kind, const char *text, uint32_t number, uint32_t modifiers, int keypad,
                   const char *application_id, int secure);
/* hajime_bridge_wake_after の時間が過ぎたら呼ぶ(裏で求めた訂正などを受け取る) */
void hajime_bridge_wake(HajimeBridge *bridge, const char *application_id, int secure);
/* 入力先から外れた */
void hajime_bridge_deactivate(HajimeBridge *bridge);

/* 直前の key・wake・deactivate の結果 */
const char *hajime_bridge_commit(HajimeBridge *bridge);
size_t hajime_bridge_preedit_count(HajimeBridge *bridge);
const char *hajime_bridge_preedit_text(HajimeBridge *bridge, size_t index, uint32_t *style);
int hajime_bridge_is_composing(HajimeBridge *bridge);
/* 0 なら wake は要らない(ミリ秒) */
uint32_t hajime_bridge_wake_after(HajimeBridge *bridge);

/* 候補の一覧を取り込む．以下の関数は取り込んだ一覧を返す */
void hajime_bridge_load_panel(HajimeBridge *bridge);
size_t hajime_bridge_candidate_count(HajimeBridge *bridge);
const char *hajime_bridge_candidate(HajimeBridge *bridge, size_t index);
/* 選んでいる候補の位置．無ければ -1 */
int32_t hajime_bridge_selected(HajimeBridge *bridge);
const char *hajime_bridge_note(HajimeBridge *bridge);
const char *hajime_bridge_hints(HajimeBridge *bridge);

#ifdef __cplusplus
}
#endif

#endif
