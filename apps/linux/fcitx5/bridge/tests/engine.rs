//! 本物のエンジン(hajime-engine-host)と確かめる．エンジンを動かし，同じ XDG_RUNTIME_DIR を渡して
//! `cargo test -- --ignored` で動かす(CI ではエンジンを動かさないので飛ばす)

use ipc::{FieldContext, Key, Modifiers};
use hajime_fcitx5_bridge::Bridge;
use std::time::{Duration, Instant};

fn context() -> FieldContext {
    FieldContext {
        application_id: Some("org.example.editor".into()),
        is_secure: false,
        preceding_text: None,
        caret: None,
    }
}

const PLAIN: Modifiers = Modifiers {
    shift: false,
    control: false,
    alt: false,
};

#[test]
#[ignore]
fn 打って変換すると候補の一覧が届き_確定できる() {
    let mut bridge = Bridge::new(None).unwrap();
    for character in "kyouhaiitenkidesu".chars() {
        assert!(bridge.key(
            Key::Character {
                text: character.to_string()
            },
            PLAIN,
            false,
            context()
        ));
    }
    assert!(bridge.preedit().iter().any(|(_, text)| !text.is_empty()));
    assert!(bridge.key(Key::Space, PLAIN, false, context()));
    // 候補の指示は別の接続で届くので，少し待つ
    let started = Instant::now();
    while bridge.load_panel_now().is_empty() && started.elapsed() < Duration::from_secs(5) {
        std::thread::sleep(Duration::from_millis(50));
    }
    assert!(!bridge.load_panel_now().is_empty(), "候補の一覧が届かない");
    assert!(bridge.key(Key::Enter, PLAIN, false, context()));
    assert_eq!(bridge.commit_text(), "今日はいい天気です");
}
