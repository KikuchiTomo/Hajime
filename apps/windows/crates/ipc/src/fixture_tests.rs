use crate::*;
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::Value;

const FIXTURES: &str = include_str!("../../../../../protocol/fixtures/messages.json");

fn round_trip<T: Serialize + DeserializeOwned>(group: &str) -> usize {
    let fixtures: Value = serde_json::from_str(FIXTURES).unwrap();
    let messages = fixtures[group].as_array().unwrap();
    for message in messages {
        let decoded: T = serde_json::from_value(message.clone())
            .unwrap_or_else(|error| panic!("{group} の {message} を読めない: {error}"));
        let encoded = serde_json::to_value(&decoded).unwrap();
        assert_eq!(&encoded, message, "{group} を読み戻すと形が変わる");
    }
    messages.len()
}

#[test]
fn 要求を読み戻せる() {
    assert!(round_trip::<Request>("requests") > 0);
}

#[test]
fn 応答を読み戻せる() {
    assert!(round_trip::<Response>("responses") > 0);
}

#[test]
fn 候補ウィンドウへの指示を読み戻せる() {
    assert!(round_trip::<UiCommand>("uiCommands") > 0);
}

#[test]
fn 枠を通しても同じ値になる() {
    let fixtures: Value = serde_json::from_str(FIXTURES).unwrap();
    for message in fixtures["requests"].as_array().unwrap() {
        let request: Request = serde_json::from_value(message.clone()).unwrap();
        let frame = framing::encode(&request).unwrap();
        let back: Request = framing::decode(&frame[framing::LENGTH_BYTES..]).unwrap();
        assert_eq!(back, request);
    }
}
