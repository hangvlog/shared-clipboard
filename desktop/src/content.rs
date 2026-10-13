use crate::{crypto, legacy, platform as p};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::Value;
pub const MAX_IMAGE: usize = 2 * 1024 * 1024;

pub fn selected<'a>(rows: &'a [Value], selection: &str) -> Option<&'a Value> {
    // AppKit sends the row index; Win32 sends the stable record ID.
    rows.iter()
        .find(|row| row["id"].as_str() == Some(selection))
        .or_else(|| selection.parse::<usize>().ok().and_then(|i| rows.get(i)))
}

pub fn decode(item: Value, keys: &[String]) -> Result<(String, Vec<u8>), String> {
    let item = legacy::decrypt(item, keys)?;
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
    Ok((
        if kind == "image" {
            String::new()
        } else {
            content.into()
        },
        image,
    ))
}

pub fn copy(item: Value, keys: &[String]) -> Result<String, String> {
    let (text, image) = decode(item, keys)?;
    p::write(&text, &image)?;
    Ok(fingerprint(&text, &image))
}

pub(crate) fn fingerprint(text: &str, image: &[u8]) -> String {
    crypto::hash(format!("{}:{}", crypto::hash(text.as_bytes()), crypto::hash(image)).as_bytes())
}
