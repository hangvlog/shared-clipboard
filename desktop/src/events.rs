//! A bounded mailbox: clipboard notifications coalesce; overload reconnects for a snapshot.
use std::{
    collections::VecDeque,
    sync::{Condvar, Mutex, OnceLock},
    time::Duration,
};
struct Inbox {
    rows: VecDeque<(i32, String)>,
    bytes: usize,
}
static QUEUE: OnceLock<(Mutex<Inbox>, Condvar)> = OnceLock::new();
fn queue() -> &'static (Mutex<Inbox>, Condvar) {
    QUEUE.get_or_init(|| {
        (
            Mutex::new(Inbox {
                rows: VecDeque::new(),
                bytes: 0,
            }),
            Condvar::new(),
        )
    })
}
pub fn send(kind: i32, data: String) {
    let (lock, signal) = queue();
    let mut inbox = lock.lock().unwrap();
    if (kind == 2 || kind == 5) && inbox.rows.iter().any(|(k, _)| *k == kind) {
        return;
    }
    if data.len() > 8_000_000 || inbox.bytes + data.len() > 8_000_000 || inbox.rows.len() >= 32 {
        // Never silently lose a remote change. Reconnection fetches the latest server item.
        if kind == 3 {
            inbox.rows.retain(|(k, _)| *k != 3 && *k != 10);
            inbox.bytes = inbox.rows.iter().map(|(_, s)| s.len()).sum();
            inbox.rows.push_back((10, String::new()));
            signal.notify_one();
        } else {
            crate::platform::status("正在处理，请稍后重试此操作");
        }
        return;
    }
    inbox.bytes += data.len();
    inbox.rows.push_back((kind, data));
    signal.notify_one();
}
pub fn receive(timeout: Duration) -> Option<(i32, String)> {
    let (lock, signal) = queue();
    let inbox = lock.lock().unwrap();
    let (mut inbox, _) = signal
        .wait_timeout_while(inbox, timeout, |q| q.rows.is_empty())
        .unwrap();
    let row = inbox.rows.pop_front();
    if let Some((_, data)) = &row {
        inbox.bytes -= data.len();
    }
    row
}
pub fn discard_clipboard() {
    let mut q = queue().0.lock().unwrap();
    q.rows.retain(|(k, _)| *k != 2);
}
