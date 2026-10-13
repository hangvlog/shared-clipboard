//! Old encrypted records remain readable; new clipboard items are plaintext.
use crate::{crypto, state::State};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};

pub fn keys(state: &State) -> Vec<String> {
    let mut keys = vec![];
    if !state.key.is_empty() {
        keys.push(state.key.clone());
    }
    if !state.username.is_empty() {
        add(&mut keys, crypto::derive("123456789", &state.username));
    }
    keys
}
pub fn add(keys: &mut Vec<String>, key: String) {
    if !keys.contains(&key) {
        keys.push(key);
    }
}
pub fn account_key(data: &Value, username: &str) -> Result<Option<String>, String> {
    let Some(value) = data["password"].as_str().filter(|s| !s.is_empty()) else {
        return Ok(None);
    };
    if value.len() > 16384 {
        return Err("旧记录配置无效".into());
    }
    let bytes = STANDARD.decode(value).map_err(|_| "旧记录配置无效")?;
    let mut decoded = vec![];
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let pair = bytes.get(i + 1..i + 3).ok_or("旧记录配置无效")?;
            let hex = std::str::from_utf8(pair).map_err(|_| "旧记录配置无效")?;
            decoded.push(u8::from_str_radix(hex, 16).map_err(|_| "旧记录配置无效")?);
            i += 3;
        } else {
            decoded.push(bytes[i]);
            i += 1;
        }
    }
    let password = String::from_utf8(decoded).map_err(|_| "旧记录配置无效")?;
    Ok(Some(crypto::derive(&password, username)))
}
pub fn decrypt(item: Value, keys: &[String]) -> Result<Value, String> {
    if item["encrypted"] != true {
        return Ok(item);
    }
    if item["metadataOnly"] == true {
        return Err("旧记录正文尚未读取".into());
    }
    for key in keys {
        let mut plain = item.clone();
        let mut valid = true;
        for field in ["content", "preview", "imageUrl"] {
            if let Some(value) = item[field].as_str().filter(|v| !v.is_empty()) {
                if field == "imageUrl"
                    && (value.starts_with("data:") || value.starts_with("https://"))
                {
                    continue;
                }
                match crypto::open(value, key) {
                    Ok(text) => plain[field] = json!(text),
                    Err(_) => {
                        valid = false;
                        break;
                    }
                }
            }
        }
        if valid {
            plain["encrypted"] = json!(false);
            return Ok(plain);
        }
    }
    Err("此旧记录需要原密码，请从菜单选择解锁旧记录".into())
}

pub fn summary(item: &Value) -> String {
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
