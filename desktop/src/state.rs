use crate::{crypto, platform};
use serde::{Deserialize, Serialize};
use serde_json::Value;
#[derive(Serialize, Deserialize, Clone)]
pub struct Pending {
    pub id: String,
    pub bytes: usize,
}
#[derive(Serialize, Deserialize)]
#[serde(default)]
pub struct State {
    pub token: String,
    pub username: String,
    pub key: String,
    pub device: String,
    pub pending: Vec<Pending>,
    pub paused: bool,
    pub last_id: String,
    pub storage_key: String,
}
impl Default for State {
    fn default() -> Self {
        Self {
            token: String::new(),
            username: String::new(),
            key: String::new(),
            device: crypto::random_id(),
            pending: vec![],
            paused: false,
            last_id: String::new(),
            storage_key: crypto::random_key(),
        }
    }
}
impl State {
    pub fn load() -> Self {
        #[cfg(feature = "qa")]
        if let Ok(path) = std::env::var("SHARED_CLIPBOARD_QA_STATE") {
            assert!(std::env::var("SHARED_CLIPBOARD_API")
                .unwrap_or_default()
                .starts_with("http://127.0.0.1:"));
            return serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        }
        serde_json::from_str(&platform::load()).unwrap_or_default()
    }
    pub fn save(&self) -> Result<(), String> {
        #[cfg(feature = "qa")]
        if let Ok(path) = std::env::var("SHARED_CLIPBOARD_QA_STATE") {
            return std::fs::write(path, serde_json::to_string(self).unwrap())
                .map_err(|e| e.to_string());
        }
        platform::save(&serde_json::to_string(self).unwrap())
    }
    fn path(id: &str) -> Result<std::path::PathBuf, String> {
        if id.len() != 32 || !id.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err("队列索引无效".into());
        }
        Ok(platform::data_dir()?.join(format!("outbox-{id}")))
    }
    pub fn add(&mut self, item: Value) -> Result<(), String> {
        let plain = item.to_string();
        if self.pending.len() >= 8
            || self.pending.iter().map(|v| v.bytes).sum::<usize>() + plain.len() > 4 * 1024 * 1024
        {
            return Err("离线队列已满，请联网后重新同步当前内容".into());
        }
        let id = crypto::random_id();
        let path = Self::path(&id)?;
        let encrypted = crypto::seal(&plain, &self.storage_key)?;
        std::fs::write(&path, encrypted).map_err(|_| "无法保存待发送内容")?;
        self.pending.push(Pending {
            id,
            bytes: plain.len(),
        });
        if let Err(e) = self.save() {
            self.pending.pop();
            let _ = std::fs::remove_file(path);
            return Err(e);
        }
        Ok(())
    }
    pub fn first(&self) -> Result<Value, String> {
        let item = self.pending.first().ok_or("队列为空")?;
        let data =
            std::fs::read_to_string(Self::path(&item.id)?).map_err(|_| "待发送内容读取失败")?;
        serde_json::from_str(&crypto::open(&data, &self.storage_key)?)
            .map_err(|_| "待发送内容格式无效".into())
    }
    pub fn acknowledge(&mut self) -> Result<(), String> {
        let first = self.pending.remove(0);
        if let Err(e) = self.save() {
            self.pending.insert(0, first);
            return Err(e);
        }
        let _ = std::fs::remove_file(Self::path(&first.id)?);
        Ok(())
    }
    pub fn clear_pending(&mut self) {
        for item in self.pending.drain(..) {
            if let Ok(path) = Self::path(&item.id) {
                let _ = std::fs::remove_file(path);
            }
        }
    }
}
