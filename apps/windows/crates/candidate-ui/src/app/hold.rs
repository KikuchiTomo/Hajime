//! 押し続けて出すキーの案内(macOS の CandidatePanelController.modifiersChanged と同じ決まり)．
//! 分岐図を出しているあいだ，修飾キーだけを決まった時間(motion.branch-map.hint-hold)押し続けたら，その修飾キーを使うキーの案内を
//! 濃くしながら(motion.branch-map.hint-fade)出す．ほかのキーと組み合わせて押したとき(⇧→ など)は出さない．離したらすぐに消す

use std::time::{Duration, Instant};

use crate::scene::Held;

fn hold_duration() -> Duration {
    Duration::from_millis(tokens::motion::branch_map::HINT_HOLD as u64)
}

fn fade_duration() -> Duration {
    Duration::from_millis(tokens::motion::branch_map::HINT_FADE as u64)
}

#[derive(Debug, Default)]
pub(super) struct HintHold {
    /// 押している修飾キー
    held: Held,
    /// 今の修飾キーを押し始めた時刻．押していなければ None
    pressed_at: Option<Instant>,
    /// 案内を出し始めた時刻．まだ出していなければ None
    revealed_at: Option<Instant>,
    /// 押しているあいだにほかのキーを押した(組み合わせて押しただけなので，離すまで出さない)
    combined: bool,
}

impl HintHold {
    /// 読んだ修飾キーの状態を入れる．描き直す必要があれば true
    pub fn update(&mut self, held: Held, now: Instant) -> bool {
        if held.is_empty() {
            // 離したら，すぐに消す(離すのは次の操作の始まりなので待たせない)
            let shown = self.revealed_at.is_some();
            *self = Self::default();
            return shown;
        }
        if self.revealed_at.is_some() {
            // すでに出しているときに修飾キーを足した・減らしたら，待たずに出す案内を替える
            let changed = self.held != held;
            self.held = held;
            return changed;
        }
        if self.pressed_at.is_none() || self.held != held {
            self.pressed_at = Some(now);
            self.held = held;
        }
        let waited = self
            .pressed_at
            .is_some_and(|start| now.duration_since(start) >= hold_duration());
        if waited && !self.combined {
            self.revealed_at = Some(now);
            return true;
        }
        false
    }

    /// 修飾キーを押しているあいだに，ほかのキーを押して分岐図が変わった．まだ出していなければ，離すまで出さない
    pub fn other_key(&mut self) {
        if self.pressed_at.is_some() && self.revealed_at.is_none() {
            self.combined = true;
        }
    }

    /// 出す案内の修飾キーと濃さ．出していなければ空
    pub fn shown(&self, now: Instant) -> (Held, f32) {
        match self.revealed_at {
            Some(start) => {
                let progress =
                    now.duration_since(start).as_secs_f32() / fade_duration().as_secs_f32();
                (self.held, progress.clamp(0.0, 1.0))
            }
            None => (Held::default(), 1.0),
        }
    }

    /// 濃くしている途中か
    pub fn is_fading(&self, now: Instant) -> bool {
        self.revealed_at
            .is_some_and(|start| now.duration_since(start) < fade_duration())
    }

    pub fn reset(&mut self) {
        *self = Self::default();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHIFT: Held = Held {
        shift: true,
        control: false,
        alt: false,
    };
    const ALT: Held = Held {
        shift: false,
        control: false,
        alt: true,
    };

    #[test]
    fn 修飾キーだけを押し続けたら出し_濃くしながら出し_離したらすぐ消す() {
        let start = Instant::now();
        let mut hold = HintHold::default();
        assert!(!hold.update(SHIFT, start));
        assert!(!hold.update(SHIFT, start + hold_duration() / 2));
        assert_eq!(hold.shown(start).0, Held::default());
        let revealed = start + hold_duration();
        assert!(hold.update(SHIFT, revealed));
        assert_eq!(hold.shown(revealed), (SHIFT, 0.0));
        assert!(hold.is_fading(revealed + fade_duration() / 2));
        assert_eq!(hold.shown(revealed + fade_duration()), (SHIFT, 1.0));
        assert!(!hold.is_fading(revealed + fade_duration()));
        // 出しているときに修飾キーを替えたら，待たずに替える
        assert!(hold.update(ALT, revealed + fade_duration()));
        assert_eq!(hold.shown(revealed + fade_duration()).0, ALT);
        // 離したら，すぐ消す
        assert!(hold.update(Held::default(), revealed + fade_duration()));
        assert_eq!(hold.shown(revealed + fade_duration()).0, Held::default());
    }

    #[test]
    fn ほかのキーと組み合わせて押したら_離すまで出さない() {
        let start = Instant::now();
        let mut hold = HintHold::default();
        hold.update(SHIFT, start);
        hold.other_key();
        assert!(!hold.update(SHIFT, start + hold_duration() * 3));
        assert_eq!(hold.shown(start + hold_duration() * 3).0, Held::default());
        // 離して押し直せば，また出せる
        hold.update(Held::default(), start + hold_duration() * 3);
        let again = start + hold_duration() * 4;
        hold.update(SHIFT, again);
        assert!(hold.update(SHIFT, again + hold_duration()));
    }

    #[test]
    fn 押していないときにほかのキーを押しても_次に押し続けたら出す() {
        let start = Instant::now();
        let mut hold = HintHold::default();
        hold.other_key();
        hold.update(ALT, start);
        assert!(hold.update(ALT, start + hold_duration()));
    }
}
