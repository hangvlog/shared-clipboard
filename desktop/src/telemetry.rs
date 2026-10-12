//! Fixed event names only: no account identifiers, clipboard text, URLs or errors.
use crate::{crypto, platform};
use serde_json::json;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    OnceLock,
};
static SENDING: AtomicBool = AtomicBool::new(false);
static SESSION: OnceLock<String> = OnceLock::new();
pub fn started() {
    if std::env::var("SHARED_CLIPBOARD_LOGS").as_deref() == Ok("off")
        || SENDING.swap(true, Ordering::AcqRel)
    {
        return;
    }
    let endpoint = std::env::var("SHARED_CLIPBOARD_LOG_URL")
        .unwrap_or("https://loghang.clawkit.chat/api/front/client-log/report".into());
    if !endpoint.starts_with("https://") {
        SENDING.store(false, Ordering::Release);
        return;
    }
    let record = json!({"level":"info","type":"behavior","source":"shared-clipboard-desktop","message":"desktop_started","appVersion":env!("CARGO_PKG_VERSION"),"deviceInfo":std::env::consts::OS,"sessionId":SESSION.get_or_init(crypto::random_id)});
    std::thread::spawn(move || {
        let _ = platform::request("POST", &endpoint, "", &record);
        SENDING.store(false, Ordering::Release);
    });
}
