//! Revocable `shared-clipboard` device sessions (`/codex-remote/sso`).
//! Access tokens last at most 24 hours; the device-bound refresh credential renews them with no
//! total lifetime, so only an explicit server refusal (401/403) asks the user to sign in again.
use crate::{endpoints::endpoint, platform, state::State};
use serde_json::{json, Value};
use std::time::{SystemTime, UNIX_EPOCH};

pub const RENEW_BEFORE: u64 = 2 * 60 * 60;
pub const EXPIRED: &str = "登录已过期，请重新登录";
pub const OFFLINE: &str = "登录续期失败，请检查网络，稍后自动重试";
const CLIENT: &str = "shared-clipboard";

pub trait Http {
    /// Status (0 when the request never completed) and response body.
    fn post(&self, url: &str, body: &Value) -> (i32, String);
}

pub struct Native;
impl Http for Native {
    fn post(&self, url: &str, body: &Value) -> (i32, String) {
        platform::raw("POST", url, "", body)
    }
}

#[derive(Debug, PartialEq)]
pub enum Renewal {
    /// Nothing to do: still fresh, signed out, or an earlier trigger already renewed this token.
    Current,
    Renewed,
    /// The server refused the credential; the user must sign in again.
    Rejected(String),
    /// Network or server trouble; keep the session and retry later.
    Unavailable(String),
}

pub struct Grant {
    pub token: String,
    pub refresh_token: String,
    pub expires_at: u64,
    pub username: String,
}

pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn grant(http: &dyn Http, path: &str, body: Value, now: u64) -> Result<Grant, Renewal> {
    let (code, raw) = http.post(&endpoint(path), &body);
    let data: Value = serde_json::from_str(&raw).unwrap_or(Value::Null);
    let detail = data["detail"].as_str().filter(|s| !s.is_empty());
    if code == 401 || code == 403 {
        return Err(Renewal::Rejected(detail.unwrap_or(EXPIRED).into()));
    }
    let token = data["token"].as_str().unwrap_or("");
    let refresh_token = data["refresh_token"].as_str().unwrap_or("");
    if code != 200 || token.is_empty() || refresh_token.is_empty() {
        return Err(Renewal::Unavailable(if code == 0 {
            "网络错误，请检查网络后重试".into()
        } else {
            format!("服务暂不可用，请稍后重试（{code}）")
        }));
    }
    Ok(Grant {
        token: token.into(),
        refresh_token: refresh_token.into(),
        expires_at: now + data["expires_in"].as_u64().unwrap_or(3600),
        username: data["user"]["username"].as_str().unwrap_or("").into(),
    })
}

pub fn login(
    http: &dyn Http,
    username: &str,
    password: &str,
    device: &str,
    now: u64,
) -> Result<Grant, String> {
    let body = json!({"username":username,"password":password,"device_id":device,"client":CLIENT});
    match grant(http, "/codex-remote/sso/password", body, now) {
        Ok(mut g) => {
            if g.username.is_empty() {
                g.username = username.into();
            }
            Ok(g)
        }
        Err(Renewal::Rejected(m) | Renewal::Unavailable(m)) => Err(m),
        Err(_) => Err("登录失败，请稍后重试".into()),
    }
}

/// Renew the access token that was refused or is about to expire. Triggers that observed the
/// same `stale` token share one request: once it is replaced, later callers get `Current`.
pub fn renew(http: &dyn Http, state: &mut State, stale: &str, now: u64) -> Renewal {
    if state.token.is_empty() || state.token != stale {
        return Renewal::Current;
    }
    if state.refresh_token.is_empty() {
        // Legacy 24-hour `/auth/login` token: nothing can renew it.
        return Renewal::Rejected(EXPIRED.into());
    }
    let body = json!({"refresh_token":state.refresh_token,"device_id":state.device});
    match grant(http, "/codex-remote/sso/refresh", body, now) {
        Ok(g) => {
            state.token = g.token;
            state.refresh_token = g.refresh_token;
            state.expires_at = g.expires_at;
            if !g.username.is_empty() {
                state.username = g.username;
            }
            Renewal::Renewed
        }
        Err(outcome) => outcome,
    }
}

pub fn due(state: &State, now: u64) -> bool {
    !state.token.is_empty() && now + RENEW_BEFORE >= state.expires_at
}

/// Renew when less than `RENEW_BEFORE` remains; a cheap no-op while the token is fresh.
pub fn ensure_fresh(http: &dyn Http, state: &mut State, now: u64) -> Renewal {
    if !due(state, now) {
        return Renewal::Current;
    }
    let stale = state.token.clone();
    renew(http, state, &stale, now)
}

/// Seconds until proactive renewal is due; `None` when signed out.
pub fn until_due(state: &State, now: u64) -> Option<u64> {
    if state.token.is_empty() {
        return None;
    }
    Some(
        state
            .expires_at
            .saturating_sub(RENEW_BEFORE)
            .saturating_sub(now),
    )
}

/// Revoke the refresh credential server-side; failures are ignored after local sign-out.
pub fn logout(http: &dyn Http, refresh_token: &str, device: &str) {
    if !refresh_token.is_empty() {
        let body = json!({"refresh_token":refresh_token,"device_id":device});
        http.post(&endpoint("/codex-remote/sso/logout"), &body);
    }
}

#[cfg(test)]
#[path = "session_tests.rs"]
mod tests;
