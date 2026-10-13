fn api() -> String {
    std::env::var("SHARED_CLIPBOARD_API")
        .ok()
        .filter(|s| s.starts_with("https://") || s.starts_with("http://127.0.0.1:"))
        .unwrap_or("https://clawkit.chat/api".into())
}
pub fn ws() -> String {
    std::env::var("SHARED_CLIPBOARD_WS")
        .ok()
        .filter(|s| s.starts_with("wss://") || s.starts_with("ws://127.0.0.1:"))
        .unwrap_or("wss://clawkit.chat".into())
        + "/socket.io/?EIO=4&transport=websocket"
}
pub fn endpoint(path: &str) -> String {
    api() + path
}
