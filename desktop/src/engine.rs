use crate::{crypto, platform as p, state::State};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};
use std::time::{Duration, Instant};
const MAX_IMAGE: usize = 2 * 1024 * 1024;
fn api() -> String {
    std::env::var("SHARED_CLIPBOARD_API")
        .ok()
        .filter(|s| s.starts_with("https://") || s.starts_with("http://127.0.0.1:"))
        .unwrap_or("https://clawkit.chat/api".into())
}
fn ws() -> String {
    std::env::var("SHARED_CLIPBOARD_WS")
        .ok()
        .filter(|s| s.starts_with("wss://") || s.starts_with("ws://127.0.0.1:"))
        .unwrap_or("wss://clawkit.chat".into())
        + "/socket.io/?EIO=4&transport=websocket"
}
fn endpoint(path: &str) -> String {
    api() + path
}
fn summary(item: &Value) -> String {
    let kind = item["contentType"].as_str().unwrap_or("text");
    let text = if item["encrypted"] == true {
        "[加密记录]".into()
    } else if kind == "image" {
        "[图片]".into()
    } else {
        item["content"]
            .as_str()
            .unwrap_or("")
            .chars()
            .take(80)
            .collect::<String>()
            .replace(['\n', '\r'], " ")
    };
    format!(
        "{}  {}",
        item["deviceName"].as_str().unwrap_or("设备"),
        text
    )
}
fn decrypt(mut item: Value, s: &State) -> Result<Value, String> {
    if item["encrypted"] == true {
        if s.key.is_empty() {
            return Err("请登录并填写相同的剪贴板加密密码".into());
        }
        for field in ["content", "preview", "imageUrl"] {
            if let Some(value) = item[field].as_str().filter(|v| !v.is_empty()) {
                // Legacy rich imageUrl may be an unencrypted URI.
                if field == "imageUrl"
                    && (value.starts_with("data:") || value.starts_with("https://"))
                {
                    continue;
                }
                item[field] = Value::String(crypto::open(value, &s.key)?);
            }
        }
        item["encrypted"] = json!(false);
    }
    Ok(item)
}
fn copy(item: Value, s: &State) -> Result<String, String> {
    let item = decrypt(item, s)?;
    let kind = item["contentType"].as_str().unwrap_or("text");
    let content = item["content"].as_str().unwrap_or("");
    let source = if kind == "image" {
        content
    } else {
        item["imageUrl"].as_str().unwrap_or("")
    };
    let image = if source.starts_with("data:image/") {
        STANDARD
            .decode(source.split_once(',').ok_or("图片格式无效")?.1)
            .map_err(|_| "图片格式无效")?
    } else if kind == "image" {
        return Err("此图片为旧版云端链接，请从手机查看".into());
    } else {
        vec![]
    };
    if image.len() > MAX_IMAGE {
        return Err("图片超过 2 MiB，请使用文件传输".into());
    }
    let text = if kind == "image" { "" } else { content };
    p::write(text, &image)?;
    Ok(fingerprint(text, &image))
}
fn fingerprint(text: &str, image: &[u8]) -> String {
    crypto::hash(format!("{}:{}", crypto::hash(text.as_bytes()), crypto::hash(image)).as_bytes())
}
struct Runtime {
    state: State,
    generation: u64,
    connected: bool,
    retry: Instant,
    delay: u64,
    last_hash: String,
    history: Vec<Value>,
}
impl Runtime {
    fn reconnect(&mut self) {
        self.generation += 1;
        p::ws_close();
        self.connected = false;
        if self.state.token.is_empty() || self.state.paused {
            return;
        }
        p::status("正在连接");
        p::ws_open(&ws(), self.generation);
        self.retry = Instant::now() + Duration::from_secs(35);
    }
    fn failure(&mut self, error: String) {
        p::status(&error);
        if error.contains("登录已过期") {
            self.state.token.clear();
            self.state.key.clear();
            self.state.clear_pending();
            let _ = self.state.save();
            self.generation += 1;
            p::ws_close();
            self.connected = false;
        }
    }
    fn flush(&mut self) -> Result<(), String> {
        while self.connected && !self.state.paused && !self.state.pending.is_empty() {
            let item = p::request(
                "POST",
                &endpoint("/clipboard/add"),
                &self.state.token,
                &self.state.first()?,
            )?;
            p::ws_send(&format!(
                "42{}",
                json!(["clipboard_sync",{"item":{"id":item["id"]}}])
            ));
            self.state.last_id = item["id"].as_str().unwrap_or("").into();
            self.state.acknowledge()?;
        }
        Ok(())
    }
    fn capture(&mut self) -> Result<(), String> {
        if self.state.token.is_empty() || self.state.paused {
            return Ok(());
        }
        let (text, image) = p::clipboard()?;
        if text.is_empty() && image.is_empty() {
            return Ok(());
        }
        if text.len() > 100000 || image.len() > MAX_IMAGE {
            return Err("内容过大：文本上限 100KB，图片上限 2MiB".into());
        }
        let hash = fingerprint(&text, &image);
        if hash == self.last_hash {
            return Ok(());
        }
        let kind = if image.is_empty() {
            "text"
        } else if text.is_empty() {
            "image"
        } else {
            "rich"
        };
        let uri = if image.is_empty() {
            String::new()
        } else {
            format!("data:image/png;base64,{}", STANDARD.encode(&image))
        };
        let content = if kind == "image" { uri.clone() } else { text };
        let mut image_url = if kind == "rich" { uri } else { String::new() };
        let content_hash = crypto::hash(content.as_bytes());
        let encrypted = !self.state.key.is_empty();
        let content = if encrypted {
            if !image_url.is_empty() {
                image_url = crypto::seal(&image_url, &self.state.key)?
            };
            crypto::seal(&content, &self.state.key)?
        } else {
            content
        };
        self.state.add(json!({"content":content,"content_type":kind,"device_id":self.state.device,"device_name":if cfg!(target_os="macos"){"Mac"}else{"Windows"},"encrypted":encrypted,"content_hash":content_hash,"image_url":if image_url.is_empty(){Value::Null}else{json!(image_url)}}))?;
        self.last_hash = hash;
        self.flush()?;
        p::status(if self.connected {
            "已连接 · 自动同步"
        } else {
            "离线 · 已保存在本机等待同步"
        });
        Ok(())
    }
    fn socket(&mut self, data: &str) -> Result<(), String> {
        let envelope: Value = serde_json::from_str(data).map_err(|_| "连接数据无效")?;
        if envelope["generation"].as_u64() != Some(self.generation) {
            return Ok(());
        }
        let packet = envelope["text"].as_str().unwrap_or("");
        if packet.starts_with('0') {
            p::ws_send("40");
        } else if packet == "2" {
            p::ws_send("3");
        } else if packet.starts_with("40") {
            p::ws_send(&format!(
                "421{}",
                json!(["register_device",{"deviceId":self.state.device,"deviceType":"desktop","deviceName":if cfg!(target_os="macos"){"Mac"}else{"Windows"},"platform":std::env::consts::OS,"appVersion":env!("CARGO_PKG_VERSION"),"token":self.state.token}])
            ));
        } else if let Some(ack) = packet.strip_prefix("431") {
            let ack: Value = serde_json::from_str(ack).map_err(|_| "注册失败")?;
            if ack[0]["success"] != true {
                return Err("登录已过期，请重新登录".into());
            }
            self.connected = true;
            self.delay = 1;
            p::status("已连接 · 自动同步");
            self.flush()?;
            // Fetch only the latest record after reconnect. History stays server-side.
            let rows = p::request(
                "GET",
                &endpoint("/clipboard/history?limit=1"),
                &self.state.token,
                &Value::Null,
            )?;
            if let Some(item) = rows.as_array().and_then(|a| a.first()) {
                self.receive(item.clone())?;
            }
        } else if let Some(event) = packet.strip_prefix("42") {
            let event: Value = serde_json::from_str(event).map_err(|_| "同步消息无效")?;
            if event[0] == "clipboard_sync" {
                self.receive(event[1]["item"].clone())?;
            }
        }
        Ok(())
    }
    fn receive(&mut self, item: Value) -> Result<(), String> {
        let id = item["id"].as_str().unwrap_or("");
        if id.is_empty() || id == self.state.last_id {
            return Ok(());
        }
        if item["deviceId"] != self.state.device {
            self.last_hash = copy(item.clone(), &self.state)?;
        }
        self.state.last_id = id.into();
        self.state.save()
    }
    fn event(&mut self, kind: i32, data: String) -> Result<(), String> {
        match kind {
            1 => {
                let v: Value = serde_json::from_str(&data).map_err(|_| "登录输入无效")?;
                let logged = p::request(
                    "POST",
                    &endpoint("/auth/login"),
                    "",
                    &json!({"username":v["username"],"password":v["password"]}),
                )?;
                let username = logged["user"]["username"]
                    .as_str()
                    .ok_or("登录响应无效")?
                    .to_string();
                let token = logged["token"].as_str().ok_or("登录响应无效")?.to_string();
                let password = v["encryption"].as_str().unwrap_or("");
                let key = if password.is_empty() {
                    String::new()
                } else {
                    crypto::derive(password, &username)
                };
                self.state.clear_pending();
                self.state = State {
                    username,
                    token,
                    key,
                    device: self.state.device.clone(),
                    ..State::default()
                };
                self.state.save()?;
                p::reset_clipboard();
                crate::events::discard_clipboard();
                self.last_hash.clear();
                self.history.clear();
                self.reconnect();
            }
            2 => self.capture()?,
            3 => self.socket(&data)?,
            4 => {
                if data.parse::<u64>().ok() == Some(self.generation) {
                    self.connected = false;
                    self.retry = Instant::now() + Duration::from_secs(self.delay);
                    self.delay = (self.delay * 2).min(60);
                    p::status("离线 · 自动重连");
                }
            }
            5 => {
                let rows = p::request(
                    "GET",
                    &endpoint("/clipboard/history?limit=50&metadata_only=true"),
                    &self.state.token,
                    &Value::Null,
                )?;
                self.history = rows.as_array().cloned().unwrap_or_default();
                let labels = self
                    .history
                    .iter()
                    .map(|v| summary(&decrypt(v.clone(), &self.state).unwrap_or(v.clone())))
                    .collect::<Vec<_>>();
                p::history(&labels);
            }
            6 => {
                if let Some(item) = data.parse::<usize>().ok().and_then(|i| self.history.get(i)) {
                    let full = p::request(
                        "GET",
                        &endpoint(&format!(
                            "/clipboard/item/{}",
                            item["id"].as_str().unwrap_or("")
                        )),
                        &self.state.token,
                        &Value::Null,
                    )?;
                    self.last_hash = copy(full, &self.state)?;
                }
            }
            7 => {
                self.state.paused = !self.state.paused;
                self.state.save()?;
                self.reconnect();
                if self.state.paused {
                    p::status("同步已暂停")
                }
            }
            8 => {
                self.generation += 1;
                p::ws_close();
                self.connected = false;
                self.state.clear_pending();
                self.state = State {
                    device: self.state.device.clone(),
                    ..State::default()
                };
                self.state.save()?;
                self.last_hash.clear();
                self.history.clear();
                p::status("未登录");
            }
            9 => self.history.clear(),
            10 => self.reconnect(),
            _ => {}
        }
        Ok(())
    }
}
pub fn run() {
    let mut r = Runtime {
        state: State::load(),
        generation: 0,
        connected: false,
        retry: Instant::now(),
        delay: 1,
        last_hash: String::new(),
        history: vec![],
    };
    r.reconnect();
    if r.state.token.is_empty() {
        p::status("请登录同一个账号")
    }
    loop {
        let wait = if !r.connected && !r.state.token.is_empty() && !r.state.paused {
            r.retry.saturating_duration_since(Instant::now())
        } else if r.connected && !r.state.pending.is_empty() {
            Duration::from_secs(15)
        } else {
            Duration::from_secs(86400)
        };
        match crate::events::receive(wait) {
            Some((kind, data)) => {
                if let Err(e) = r.event(kind, data) {
                    r.failure(e);
                }
            }
            None => {
                if r.connected {
                    if let Err(e) = r.flush() {
                        r.failure(e);
                    }
                } else {
                    r.reconnect()
                }
            }
        }
    }
}
