use super::*;
use std::cell::RefCell;

const NOW: u64 = 1_800_000_000;

#[derive(Default)]
struct Fake {
    replies: RefCell<Vec<(i32, String)>>,
    calls: RefCell<Vec<(String, Value)>>,
}
impl Fake {
    fn replying(replies: &[(i32, Value)]) -> Self {
        let fake = Fake::default();
        *fake.replies.borrow_mut() = replies
            .iter()
            .rev()
            .map(|(code, body)| (*code, body.to_string()))
            .collect();
        fake
    }
    fn paths(&self) -> Vec<String> {
        self.calls.borrow().iter().map(|(u, _)| u.clone()).collect()
    }
}
impl Http for Fake {
    fn post(&self, url: &str, body: &Value) -> (i32, String) {
        self.calls.borrow_mut().push((url.into(), body.clone()));
        self.replies
            .borrow_mut()
            .pop()
            .unwrap_or((0, String::new()))
    }
}

fn issued(token: &str, refresh: &str, seconds: u64) -> Value {
    json!({"token":token,"refresh_token":refresh,"expires_in":seconds,"user":{"username":"alice"}})
}

fn signed_in(expires_in: u64) -> State {
    State {
        token: "access-old".into(),
        refresh_token: "sid.refresh-1".into(),
        expires_at: NOW + expires_in,
        username: "alice".into(),
        device: "0123456789abcdef0123456789abcdef".into(),
        ..State::default()
    }
}

#[test]
fn login_uses_shared_clipboard_device_session() {
    let http = Fake::replying(&[(200, issued("access-1", "sid.refresh-1", 86400))]);
    let grant = login(&http, "13800000000", "pw", "device-1234", NOW).unwrap();
    assert_eq!(grant.token, "access-1");
    assert_eq!(grant.refresh_token, "sid.refresh-1");
    assert_eq!(grant.expires_at, NOW + 86400);
    assert_eq!(
        grant.username, "alice",
        "canonical account name from server"
    );
    let (url, body) = http.calls.borrow()[0].clone();
    assert!(url.ends_with("/api/codex-remote/sso/password"), "{url}");
    assert_eq!(
        body,
        json!({"username":"13800000000","password":"pw","device_id":"device-1234","client":"shared-clipboard"})
    );

    let wrong = Fake::replying(&[(401, json!({"detail":"账号或密码错误"}))]);
    assert_eq!(
        login(&wrong, "alice", "bad", "device-1234", NOW)
            .err()
            .unwrap(),
        "账号或密码错误"
    );
}

#[test]
fn renews_once_before_expiry_for_concurrent_triggers() {
    let mut fresh = signed_in(10 * 3600);
    let idle = Fake::default();
    assert_eq!(ensure_fresh(&idle, &mut fresh, NOW), Renewal::Current);
    assert!(
        idle.paths().is_empty(),
        "no request while the token is fresh"
    );
    assert_eq!(until_due(&fresh, NOW), Some(8 * 3600));

    let http = Fake::replying(&[(200, issued("access-new", "sid.refresh-1", 86400))]);
    let mut state = signed_in(3600);
    // Timer, wake and a 401 all observed the same stale token.
    assert_eq!(ensure_fresh(&http, &mut state, NOW), Renewal::Renewed);
    assert_eq!(ensure_fresh(&http, &mut state, NOW), Renewal::Current);
    assert_eq!(
        renew(&http, &mut state, "access-old", NOW),
        Renewal::Current
    );
    assert_eq!(
        http.paths().len(),
        1,
        "concurrent triggers share one refresh"
    );
    let (url, body) = http.calls.borrow()[0].clone();
    assert!(url.ends_with("/api/codex-remote/sso/refresh"), "{url}");
    assert_eq!(
        body,
        json!({"refresh_token":"sid.refresh-1","device_id":"0123456789abcdef0123456789abcdef"})
    );
    assert_eq!(state.token, "access-new");
    assert_eq!(state.expires_at, NOW + 86400);

    // A 401 on a token that is not yet due still renews immediately.
    let refused = Fake::replying(&[(200, issued("access-3", "sid.refresh-1", 86400))]);
    let mut early = signed_in(20 * 3600);
    assert_eq!(
        renew(&refused, &mut early, "access-old", NOW),
        Renewal::Renewed
    );
    assert_eq!(early.token, "access-3");
}

#[test]
fn refused_renewal_requires_sign_in() {
    for code in [401, 403] {
        let http =
            Fake::replying(&[(code, json!({"detail":"远程登录已过期或被撤销，请重新登录"}))]);
        let mut state = signed_in(60);
        assert!(matches!(
            renew(&http, &mut state, "access-old", NOW),
            Renewal::Rejected(_)
        ));
        assert!(matches!(
            renew(&http, &mut state, "access-old", NOW),
            Renewal::Rejected(_)
        ));
        assert_eq!(
            http.paths().len(),
            1,
            "a refused credential is not sent again"
        );
    }
    // Upgraded from 1.1.6 or older: a plain token with no refresh credential.
    let legacy: State = serde_json::from_str(r#"{"token":"legacy","username":"alice"}"#).unwrap();
    assert!(legacy.refresh_token.is_empty() && legacy.expires_at == 0);
    let mut legacy = legacy;
    let http = Fake::default();
    assert_eq!(
        ensure_fresh(&http, &mut legacy, NOW),
        Renewal::Rejected(EXPIRED.into())
    );
    assert!(http.paths().is_empty());

    let revoke = Fake::default();
    logout(&revoke, "sid.refresh-1", "device-1234");
    let (url, body) = revoke.calls.borrow()[0].clone();
    assert!(url.ends_with("/api/codex-remote/sso/logout"), "{url}");
    assert_eq!(
        body,
        json!({"refresh_token":"sid.refresh-1","device_id":"device-1234"})
    );
}

#[test]
fn network_failure_keeps_session() {
    for (code, body) in [(0, Value::Null), (502, json!({"detail":"bad gateway"}))] {
        let http = Fake::replying(&[(code, body)]);
        let mut state = signed_in(60);
        assert!(matches!(
            ensure_fresh(&http, &mut state, NOW),
            Renewal::Unavailable(_)
        ));
        assert_eq!(state.token, "access-old");
        assert_eq!(state.refresh_token, "sid.refresh-1");
        assert_eq!(state.expires_at, NOW + 60);
    }
    let offline = Fake::default();
    assert_eq!(
        login(&offline, "alice", "pw", "device-1234", NOW)
            .err()
            .unwrap(),
        "网络错误，请检查网络后重试"
    );
}
