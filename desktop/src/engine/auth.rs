//! Session upkeep for the sync engine: sign-in, authenticated calls, renewal triggers, sign-out.
use super::Runtime;
use crate::{
    crypto,
    endpoints::endpoint,
    legacy, platform as p,
    session::{self, Native, Renewal, EXPIRED, OFFLINE},
    state::State,
};
use serde_json::Value;
use std::time::{Duration, Instant};

const OFFLINE_RETRY: Duration = Duration::from_secs(60);
const RENEWED_PAUSE: Duration = Duration::from_secs(5 * 60);
const UNAVAILABLE: &str = "同步服务暂不可用，稍后自动重试";
const RECHECK: Duration = Duration::from_secs(30 * 60);

fn revoke(refresh_token: String, device: String) {
    if !refresh_token.is_empty() {
        std::thread::spawn(move || session::logout(&Native, &refresh_token, &device));
    }
}

impl Runtime {
    pub(super) fn sign_in(&mut self, data: &str) -> Result<(), String> {
        let v: Value = serde_json::from_str(data).map_err(|_| "登录输入无效")?;
        let grant = session::login(
            &Native,
            v["username"].as_str().unwrap_or(""),
            v["password"].as_str().unwrap_or(""),
            &self.state.device,
            session::now(),
        )?;
        let password = v["encryption"].as_str().unwrap_or("");
        let key = (!password.is_empty()).then(|| crypto::derive(password, &grant.username));
        let previous = self.state.sign_in(grant, key);
        self.legacy_keys = legacy::keys(&self.state);
        self.state.save()?;
        revoke(previous, self.state.device.clone());
        self.session_loaded();
        Ok(())
    }

    /// Adopt a session another process stored (command-line `login`/`logout`).
    pub(super) fn reload(&mut self) -> Result<(), String> {
        let stored = State::load();
        if stored.token == self.state.token && stored.refresh_token == self.state.refresh_token {
            return Ok(());
        }
        self.generation += 1;
        p::ws_close();
        self.connected = false;
        self.state = stored;
        self.legacy_keys = legacy::keys(&self.state);
        if self.state.token.is_empty() {
            self.history.clear();
            self.last_hash.clear();
            p::session(false);
            p::status("未登录");
            return Ok(());
        }
        self.session_loaded();
        Ok(())
    }

    fn session_loaded(&mut self) {
        p::reset_clipboard();
        crate::events::discard_clipboard();
        self.last_hash.clear();
        self.history.clear();
        self.renew_after = Instant::now();
        p::session(true);
        self.reconnect();
    }

    pub(super) fn sign_out(&mut self) -> Result<(), String> {
        let refresh_token = self.state.sign_out();
        self.generation += 1;
        p::ws_close();
        self.connected = false;
        self.state.save()?;
        revoke(refresh_token, self.state.device.clone());
        self.legacy_keys.clear();
        self.last_hash.clear();
        self.history.clear();
        p::session(false);
        p::status("未登录");
        Ok(())
    }

    /// Authenticated REST call; a 401 renews the session and retries once with the new token.
    pub(super) fn call(&mut self, method: &str, path: &str, body: &Value) -> Result<Value, String> {
        let stale = self.state.token.clone();
        match p::request(method, &endpoint(path), &stale, body) {
            Err(e) if e == EXPIRED => {
                self.renew(&stale)?;
                p::request(method, &endpoint(path), &self.state.token, body).map_err(|e| {
                    if e == EXPIRED {
                        UNAVAILABLE.into()
                    } else {
                        e
                    }
                })
            }
            other => other,
        }
    }

    /// `Err(EXPIRED)` only when the server refused the refresh credential.
    pub(super) fn renew(&mut self, stale: &str) -> Result<(), String> {
        let outcome = session::renew(&Native, &mut self.state, stale, session::now());
        self.settle(outcome)
    }

    /// Start-up, reconnect, timer, wake and foreground; `force` skips the offline back-off.
    pub(super) fn ensure_fresh(&mut self, force: bool) -> Result<(), String> {
        if !force && Instant::now() < self.renew_after {
            return Ok(());
        }
        let outcome = session::ensure_fresh(&Native, &mut self.state, session::now());
        self.settle(outcome)
    }

    fn settle(&mut self, outcome: Renewal) -> Result<(), String> {
        match outcome {
            Renewal::Current => Ok(()),
            Renewal::Renewed => {
                // Guards against a refresh loop should the server issue a token shorter than the window.
                self.renew_after = Instant::now() + RENEWED_PAUSE;
                self.state.save()
            }
            Renewal::Rejected(_) => Err(EXPIRED.into()),
            Renewal::Unavailable(_) => {
                self.renew_after = Instant::now() + OFFLINE_RETRY;
                Err(OFFLINE.into())
            }
        }
    }

    /// The sync socket refused the access token: renew once and reconnect with the new token.
    pub(super) fn socket_rejected(&mut self) -> Result<(), String> {
        self.connected = false;
        if std::mem::take(&mut self.socket_renewed) {
            return Err(UNAVAILABLE.into());
        }
        let stale = self.state.token.clone();
        self.renew(&stale)?;
        self.socket_renewed = true;
        self.reconnect();
        Ok(())
    }

    /// Wake (`wake`) or app activation (`active`).
    pub(super) fn resumed(&mut self, reason: &str) -> Result<(), String> {
        let wake = reason == "wake";
        let fresh = self.ensure_fresh(wake);
        let refused = matches!(&fresh, Err(e) if e == EXPIRED);
        if wake && !refused && !self.connected && !self.state.token.is_empty() && !self.state.paused
        {
            self.reconnect();
        }
        fresh
    }

    /// How long the event loop may sleep before the next proactive renewal check.
    pub(super) fn renewal_wait(&self) -> Option<Duration> {
        let seconds = session::until_due(&self.state, session::now())?;
        let due = Duration::from_secs(seconds)
            .max(self.renew_after.saturating_duration_since(Instant::now()));
        // Monotonic clocks may pause during sleep; re-read wall time periodically.
        Some(due.min(RECHECK))
    }
}
