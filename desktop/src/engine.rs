mod auth;
use crate::endpoints::{endpoint, ws};
use crate::{
    content::{self, MAX_IMAGE},
    crypto, legacy, platform as p,
    session::EXPIRED,
    state::State,
};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};
use std::time::{Duration, Instant};
struct Runtime {
    state: State,
    legacy_keys: Vec<String>,
    generation: u64,
    connected: bool,
    retry: Instant,
    delay: u64,
    last_hash: String,
    history: Vec<Value>,
    history_visible: bool,
    renew_after: Instant,
    socket_renewed: bool,
}
impl Runtime {
    fn restore_legacy_keys(&mut self) -> Result<(), String> {
        match self.call("GET", "/auth/encryption-salt", &Value::Null) {
            Ok(data) => {
                if let Ok(Some(key)) = legacy::account_key(&data, &self.state.username) {
                    legacy::add(&mut self.legacy_keys, key);
                }
            }
            Err(e) if e == EXPIRED => return Err(e),
            Err(_) => {}
        }
        Ok(())
    }

    fn reconnect(&mut self) {
        self.generation += 1;
        p::ws_close();
        self.connected = false;
        if self.state.token.is_empty() || self.state.paused {
            return;
        }
        if let Err(e) = self.ensure_fresh(false) {
            if e == EXPIRED {
                return self.failure(e);
            }
        }
        p::status("正在连接");
        p::ws_open(&ws(), self.generation);
        self.retry = Instant::now() + Duration::from_secs(35);
    }
    fn failure(&mut self, error: String) {
        p::status(&error);
        if error == EXPIRED {
            p::session(false);
            self.state.token.clear();
            self.state.refresh_token.clear();
            self.state.expires_at = 0;
            self.state.key.clear();
            self.legacy_keys.clear();
            self.state.clear_pending();
            let _ = self.state.save();
            self.generation += 1;
            p::ws_close();
            self.connected = false;
        }
    }
    fn flush(&mut self) -> Result<(), String> {
        while self.connected && !self.state.paused && !self.state.pending.is_empty() {
            let first = self.state.first()?;
            let item = self.call("POST", "/clipboard/add", &first)?;
            p::ws_send(&format!(
                "42{}",
                json!(["clipboard_sync",{"item":{"id":item["id"]}}])
            ));
            self.state.last_id = item["id"].as_str().unwrap_or("").into();
            self.state.acknowledge()?;
            if self.history_visible {
                crate::events::send(5, String::new());
            }
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
        let hash = content::fingerprint(&text, &image);
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
        let image_url = if kind == "rich" { uri } else { String::new() };
        let content_hash = crypto::hash(content.as_bytes());
        self.state.add(json!({"content":content,"content_type":kind,"device_id":self.state.device,"device_name":if cfg!(target_os="macos"){"Mac"}else{"Windows"},"encrypted":false,"content_hash":content_hash,"image_url":if image_url.is_empty(){Value::Null}else{json!(image_url)}}))?;
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
                return self.socket_rejected();
            }
            self.socket_renewed = false;
            self.restore_legacy_keys()?;
            self.connected = true;
            self.delay = 1;
            p::status("已连接 · 自动同步");
            self.flush()?;
            // Fetch only the latest record after reconnect. History stays server-side.
            let rows = self.call("GET", "/clipboard/history?limit=1", &Value::Null)?;
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
            self.last_hash = content::copy(item.clone(), &self.legacy_keys)?;
        }
        self.state.last_id = id.into();
        if self.history_visible {
            crate::events::send(5, String::new());
        }
        self.state.save()
    }
    fn event(&mut self, kind: i32, data: String) -> Result<(), String> {
        match kind {
            1 => self.sign_in(&data)?,
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
                if self.state.token.is_empty() {
                    return Err("请先登录".into());
                }
                self.restore_legacy_keys()?;
                let rows = self.call(
                    "GET",
                    "/clipboard/history?limit=50&metadata_only=true",
                    &Value::Null,
                )?;
                self.history = rows.as_array().cloned().unwrap_or_default();
                let labels = self
                    .history
                    .iter()
                    .map(|v| {
                        // Fetch one text body at a time; retain only its short label.
                        let full = if v["encrypted"] == true && v["contentType"] == "text" {
                            p::request(
                                "GET",
                                &endpoint(&format!(
                                    "/clipboard/item/{}",
                                    v["id"].as_str().unwrap_or("")
                                )),
                                &self.state.token,
                                &Value::Null,
                            )
                            .unwrap_or(v.clone())
                        } else {
                            v.clone()
                        };
                        (
                            v["id"].as_str().unwrap_or("").to_string(),
                            legacy::summary(
                                &legacy::decrypt(full, &self.legacy_keys).unwrap_or(v.clone()),
                            ),
                        )
                    })
                    .collect::<Vec<_>>();
                p::history(&labels);
            }
            6 => {
                if let Some(item) = content::selected(&self.history, &data) {
                    let path = format!("/clipboard/item/{}", item["id"].as_str().unwrap_or(""));
                    let full = self.call("GET", &path, &Value::Null)?;
                    self.last_hash = content::copy(full, &self.legacy_keys)?;
                    p::status("已复制到剪贴板");
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
            8 => self.sign_out()?,
            9 => self.history.clear(),
            10 => self.reconnect(),
            11 => {
                if self.state.token.is_empty() {
                    return Err("请先登录".into());
                }
                if !data.is_empty() {
                    self.state.key = crypto::derive(&data, &self.state.username);
                    legacy::add(&mut self.legacy_keys, self.state.key.clone());
                    self.state.save()?;
                    p::status("已添加旧记录密码");
                    if self.history_visible {
                        crate::events::send(5, String::new());
                    }
                }
            }
            12 => {
                if let Some(item) = content::selected(&self.history, &data) {
                    let id = item["id"].as_str().unwrap_or("").to_string();
                    let result = self
                        .call("GET", &format!("/clipboard/item/{id}"), &Value::Null)
                        .and_then(|item| content::decode(item, &self.legacy_keys));
                    let id = id.as_str();
                    match result {
                        Ok((text, image)) => p::detail(id, &text, &image, true),
                        Err(e) => p::detail(id, &e, &[], false),
                    }
                }
            }
            13 => self.history_visible = data == "1",
            14 => self.resumed(&data)?,
            _ => {}
        }
        Ok(())
    }
}
pub fn run() {
    let state = State::load();
    let legacy_keys = legacy::keys(&state);
    let mut r = Runtime {
        state,
        legacy_keys,
        generation: 0,
        connected: false,
        retry: Instant::now(),
        delay: 1,
        last_hash: String::new(),
        history: vec![],
        history_visible: false,
        renew_after: Instant::now(),
        socket_renewed: false,
    };
    let signed_in = !r.state.token.is_empty();
    p::session(signed_in);
    r.reconnect();
    if !signed_in {
        p::status("请登录同一个账号")
    }
    loop {
        let sync = if !r.connected && !r.state.token.is_empty() && !r.state.paused {
            r.retry.saturating_duration_since(Instant::now())
        } else if r.connected && !r.state.pending.is_empty() {
            Duration::from_secs(15)
        } else {
            Duration::from_secs(86400)
        };
        let wait = r.renewal_wait().map_or(sync, |renewal| renewal.min(sync));
        match crate::events::receive(wait) {
            Some((kind, data)) => {
                if let Err(e) = r.event(kind, data) {
                    r.failure(e);
                }
            }
            None => {
                if let Err(e) = r.ensure_fresh(false) {
                    r.failure(e);
                }
                if r.connected {
                    if let Err(e) = r.flush() {
                        r.failure(e);
                    }
                } else if Instant::now() >= r.retry {
                    r.reconnect()
                }
            }
        }
    }
}
