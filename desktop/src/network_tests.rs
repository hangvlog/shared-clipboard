//! Opt-in integration test against the isolated fixture, never production.
use crate::{events, platform as p};
use serde_json::{json, Value};
use std::time::{Duration, Instant};
#[test]
#[ignore = "requires loopback fixture on 18763"]
fn native_authenticated_socket_and_rest() {
    let base = "http://127.0.0.1:18763";
    let item = p::request(
        "POST",
        &format!("{base}/clipboard/add"),
        "fixture-a",
        &json!({"content":"native-fixture-text","device_id":"native-sender"}),
    )
    .unwrap();
    p::ws_open(
        "ws://127.0.0.1:18763/socket.io/?EIO=4&transport=websocket",
        100,
    );
    let deadline = Instant::now() + Duration::from_secs(15);
    let mut registered = false;
    while Instant::now() < deadline {
        let Some((kind, data)) = events::receive(Duration::from_secs(1)) else {
            continue;
        };
        if kind != 3 {
            continue;
        }
        let value: Value = serde_json::from_str(&data).unwrap();
        let packet = value["text"].as_str().unwrap();
        if packet.starts_with('0') {
            p::ws_send("40")
        } else if packet.starts_with("40") {
            p::ws_send(&format!(
                "421{}",
                json!(["register_device",{"deviceId":"native-test","deviceType":"desktop","token":"fixture-a"}])
            ))
        } else if let Some(ack) = packet.strip_prefix("431") {
            assert_eq!(
                serde_json::from_str::<Value>(ack).unwrap()[0]["success"],
                true
            );
            registered = true;
            break;
        }
    }
    assert!(registered, "native network bridge did not register");
    let fetched = p::request(
        "GET",
        &format!("{base}/clipboard/item/{}", item["id"].as_str().unwrap()),
        "fixture-a",
        &Value::Null,
    )
    .unwrap();
    assert_eq!(fetched["content"], "native-fixture-text");
    assert!(p::request(
        "GET",
        &format!("{base}/clipboard/item/{}", item["id"].as_str().unwrap()),
        "fixture-b",
        &Value::Null
    )
    .is_err());
    p::ws_close();
}
