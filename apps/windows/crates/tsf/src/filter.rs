#![forbid(unsafe_code)]

use ipc::{InputMode, Key, KeyChord, KeyInput, Modifiers, SessionState};

pub fn consumes(state: Option<&SessionState>, input: &KeyInput) -> bool {
    let Some(state) = state else { return false };
    if state.is_composing {
        return true;
    }
    let chord = normalized(&input.key, &input.modifiers);
    if state
        .consumed_keys
        .iter()
        .any(|bound| normalized(&bound.key, &bound.modifiers) == chord)
    {
        return true;
    }
    state.mode == InputMode::Japanese
        && matches!(input.key, Key::Character { .. })
        && !input.modifiers.control
        && !input.modifiers.alt
}

fn normalized(key: &Key, modifiers: &Modifiers) -> KeyChord {
    let (key, shift) = match key {
        Key::Character { text } => {
            let is_letter = text.chars().next().is_some_and(char::is_alphabetic);
            (
                Key::Character {
                    text: text.to_lowercase(),
                },
                modifiers.shift && is_letter,
            )
        }
        other => (other.clone(), modifiers.shift),
    };
    KeyChord {
        key,
        modifiers: Modifiers {
            shift,
            control: modifiers.control,
            alt: modifiers.alt,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plain() -> Modifiers {
        Modifiers {
            shift: false,
            control: false,
            alt: false,
        }
    }

    fn input(key: Key, modifiers: Modifiers) -> KeyInput {
        KeyInput {
            key,
            modifiers,
            key_label: None,
            is_keypad: false,
        }
    }

    fn state(mode: InputMode, is_composing: bool, consumed_keys: Vec<KeyChord>) -> SessionState {
        SessionState {
            mode,
            is_composing,
            consumed_keys,
            wake_after_milliseconds: None,
            preceding_text_length: None,
        }
    }

    #[test]
    fn エンジンにつながっていなければ受け取らない() {
        assert!(!consumes(
            None,
            &input(Key::Character { text: "a".into() }, plain())
        ));
    }

    #[test]
    fn 組み立て中はすべて受け取る() {
        let composing = state(InputMode::Japanese, true, vec![]);
        assert!(consumes(Some(&composing), &input(Key::Left, plain())));
    }

    #[test]
    fn 日本語のモードでは修飾キーなしの文字を受け取る() {
        let idle = state(InputMode::Japanese, false, vec![]);
        assert!(consumes(
            Some(&idle),
            &input(Key::Character { text: "k".into() }, plain())
        ));
        let control = Modifiers {
            control: true,
            ..plain()
        };
        assert!(!consumes(
            Some(&idle),
            &input(Key::Character { text: "c".into() }, control)
        ));
        assert!(!consumes(Some(&idle), &input(Key::Left, plain())));
    }

    #[test]
    fn 英数のモードでは表のキーだけを受け取る() {
        let direct = state(
            InputMode::Direct,
            false,
            vec![
                KeyChord {
                    key: Key::HankakuZenkaku,
                    modifiers: plain(),
                },
                KeyChord {
                    key: Key::Character { text: "j".into() },
                    modifiers: Modifiers {
                        shift: true,
                        control: true,
                        alt: false,
                    },
                },
            ],
        );
        assert!(consumes(
            Some(&direct),
            &input(Key::HankakuZenkaku, plain())
        ));
        assert!(!consumes(
            Some(&direct),
            &input(Key::Character { text: "a".into() }, plain())
        ));
        let shifted = Modifiers {
            shift: true,
            control: true,
            alt: false,
        };
        assert!(consumes(
            Some(&direct),
            &input(Key::Character { text: "J".into() }, shifted)
        ));
    }

    #[test]
    fn 英字でない文字の_shift_は数えない() {
        let idle = state(
            InputMode::Direct,
            false,
            vec![KeyChord {
                key: Key::Character { text: "!".into() },
                modifiers: Modifiers {
                    control: true,
                    ..plain()
                },
            }],
        );
        let pressed = Modifiers {
            shift: true,
            control: true,
            alt: false,
        };
        assert!(consumes(
            Some(&idle),
            &input(Key::Character { text: "!".into() }, pressed)
        ));
    }
}
