//! Alt の付いた表のキー(Ctrl+Alt+E の絵文字のパレットなど)を，TSF の予約したキー(PreserveKey)として登録する．
//! Windows 11 のメモ帳などの XAML の入力欄では，Ctrl+Alt+文字が AltGr の文字入力として扱われ，キーのシンクを通らずに
//! アプリへ渡る(「€」などが入り，パレットが開かない)．予約したキーはアプリより先に OnPreservedKey で受け取れる

use ipc::{Key, KeyChord};
use windows::Win32::UI::Input::KeyboardAndMouse::{GetKeyboardLayout, VkKeyScanExW};
use windows::Win32::UI::TextServices::{
    ITfKeystrokeMgr, TF_MOD_ALT, TF_MOD_CONTROL, TF_MOD_SHIFT, TF_PRESERVEDKEY,
};
use windows_core::GUID;

/// 予約したキーの識別子のもと．末尾の 2 バイトに表の中の番号を入れる
const BASE: GUID = GUID::from_u128(0x6f0b3c1e_5a2d_4e8b_9c47_2d1a8e5b0000);
/// 一度に予約するキーの数の上限(表に Alt の付いたキーを並べすぎても，登録を増やしすぎない)
const LIMIT: usize = 64;

/// 予約した 1 つのキー
pub struct Preserved {
    pub guid: GUID,
    pub chord: KeyChord,
    key: TF_PRESERVEDKEY,
}

impl Preserved {
    /// 予約した仮想キー
    pub fn vk(&self) -> u16 {
        self.key.uVKey as u16
    }
}

/// chords を予約し直す．前に予約したキーは外す．登録できないキー(今の配列で打てない文字など)は飛ばす
pub fn replace(
    keystrokes: &ITfKeystrokeMgr,
    client_id: u32,
    current: &mut Vec<Preserved>,
    chords: &[KeyChord],
) {
    if current.len() == chords.len()
        && current
            .iter()
            .zip(chords)
            .all(|(preserved, chord)| preserved.chord == *chord)
    {
        return;
    }
    clear(keystrokes, current);
    // SAFETY: 引数は 0(この入力のスレッド)だけ
    let layout = unsafe { GetKeyboardLayout(0) };
    for (index, chord) in chords.iter().take(LIMIT).enumerate() {
        let Some(key) = preserved_key(chord, layout) else {
            continue;
        };
        let guid = GUID::from_u128(BASE.to_u128() + index as u128);
        // SAFETY: guid と key は呼び出しのあいだ生きている
        if unsafe { keystrokes.PreserveKey(client_id, &guid, &key, &[]) }.is_ok() {
            current.push(Preserved {
                guid,
                chord: chord.clone(),
                key,
            });
        }
    }
}

/// 予約したキーをすべて外す
pub fn clear(keystrokes: &ITfKeystrokeMgr, current: &mut Vec<Preserved>) {
    for preserved in current.drain(..) {
        // SAFETY: guid と key は呼び出しのあいだ生きている
        let _ = unsafe { keystrokes.UnpreserveKey(&preserved.guid, &preserved.key) };
    }
}

fn preserved_key(
    chord: &KeyChord,
    layout: windows::Win32::UI::Input::KeyboardAndMouse::HKL,
) -> Option<TF_PRESERVEDKEY> {
    let mut modifiers = 0;
    if chord.modifiers.alt {
        modifiers |= TF_MOD_ALT;
    }
    if chord.modifiers.control {
        modifiers |= TF_MOD_CONTROL;
    }
    if chord.modifiers.shift {
        modifiers |= TF_MOD_SHIFT;
    }
    let vk = match &chord.key {
        Key::Character { text } => {
            let mut characters = text.encode_utf16();
            let (Some(unit), None) = (characters.next(), characters.next()) else {
                return None;
            };
            // SAFETY: 文字と配列を渡すだけ
            let scan = unsafe { VkKeyScanExW(unit, layout) };
            if scan == -1 {
                return None;
            }
            let shift_state = (scan as u16 >> 8) & 0xff;
            // Ctrl や Alt を押して打つ文字(AltGr の文字)は，その組み合わせを予約できないので飛ばす
            if shift_state & 0b110 != 0 {
                return None;
            }
            // 英字でない文字を打つのに Shift が要る配列では，Shift も合わせる(US 配列の「<」など)
            if shift_state & 1 != 0 {
                modifiers |= TF_MOD_SHIFT;
            }
            u32::from(scan as u16 & 0xff)
        }
        other => u32::from(crate::key::named_vk(other)?),
    };
    Some(TF_PRESERVEDKEY {
        uVKey: vk,
        uModifiers: modifiers,
    })
}
