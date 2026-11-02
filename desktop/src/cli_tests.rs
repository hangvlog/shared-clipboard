use super::*;
use serde_json::Value;
use std::cell::RefCell;

#[derive(Default)]
struct Fake {
    replies: RefCell<Vec<(i32, String)>>,
    calls: RefCell<Vec<(String, Value)>>,
}
impl Http for Fake {
    fn post(&self, url: &str, body: &Value) -> (i32, String) {
        self.calls.borrow_mut().push((url.into(), body.clone()));
        self.replies.borrow_mut().pop().unwrap_or((0, String::new()))
    }
}
fn fake(replies: &[(i32, Value)]) -> Fake {
    let f = Fake::default();
    *f.replies.borrow_mut() = replies.iter().rev().map(|(c, b)| (*c, b.to_string())).collect();
    f
}
fn existing() -> State {
    State {
        token: "old-access".into(),
        refresh_token: "sid.old-refresh".into(),
        username: "hang".into(),
        key: "legacy-key".into(),
        device: "0123456789abcdef0123456789abcdef".into(),
        ..State::default()
    }
}
fn issued(user: &str) -> Value {
    json!({"token":"new-access","refresh_token":"sid.new-refresh","expires_in":86400,"user":{"username":user}})
}

#[test]
fn command_login_keeps_device_and_revokes_the_replaced_session() {
    let http = fake(&[(200, issued("hang")), (200, json!({"revoked":true}))]);
    let mut state = existing();
    sign_in(&http, &mut state, " 15700000000 ", "secret").unwrap();
    let calls = http.calls.borrow();
    assert!(calls[0].0.ends_with("/codex-remote/sso/password"));
    assert_eq!(calls[0].1["username"], "15700000000");
    assert_eq!(calls[0].1["client"], "shared-clipboard");
    assert_eq!(calls[0].1["device_id"], "0123456789abcdef0123456789abcdef");
    assert!(calls[1].0.ends_with("/codex-remote/sso/logout"));
    assert_eq!(calls[1].1["refresh_token"], "sid.old-refresh");
    assert_eq!(state.token, "new-access");
    assert_eq!(state.refresh_token, "sid.new-refresh");
    assert_eq!(state.device, "0123456789abcdef0123456789abcdef");
    assert_eq!(state.key, "legacy-key");
    let shown = status(&state).to_string();
    assert!(shown.contains("\"renewable\":true") && !shown.contains("new-access") && !shown.contains("refresh"));
}

#[test]
fn command_login_rejection_and_missing_input_keep_the_stored_session() {
    let http = fake(&[(401, json!({"detail":"账号或密码错误"}))]);
    let mut state = existing();
    assert_eq!(sign_in(&http, &mut state, "hang", "wrong").unwrap_err(), "账号或密码错误");
    assert_eq!(state.refresh_token, "sid.old-refresh");
    assert!(sign_in(&http, &mut state, "hang", "").is_err());
    assert_eq!(http.calls.borrow().len(), 1);
}

#[test]
fn another_account_drops_the_legacy_key_and_sign_out_returns_the_credential() {
    let http = fake(&[(200, issued("someone-else")), (200, json!({}))]);
    let mut state = existing();
    sign_in(&http, &mut state, "someone-else", "secret").unwrap();
    assert!(state.key.is_empty());
    assert_eq!(state.sign_out(), "sid.new-refresh");
    assert!(state.token.is_empty() && state.refresh_token.is_empty());
    assert_eq!(state.device, "0123456789abcdef0123456789abcdef");
}

#[test]
fn piped_password_drops_byte_order_mark_and_line_ending_only() {
    assert_eq!(password_line("\u{feff}123456789\r\n"), "123456789");
    assert_eq!(password_line(" pass word \n"), " pass word ");
}
