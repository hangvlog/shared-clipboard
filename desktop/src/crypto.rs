use base64::{engine::general_purpose::STANDARD, Engine};
use ring::{
    aead, digest, pbkdf2,
    rand::{SecureRandom, SystemRandom},
};
use std::num::NonZeroU32;
pub fn hash(bytes: &[u8]) -> String {
    digest::digest(&digest::SHA256, bytes)
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
pub fn derive(password: &str, username: &str) -> String {
    let salt = digest::digest(&digest::SHA256, username.as_bytes());
    let mut key = [0u8; 32];
    pbkdf2::derive(
        pbkdf2::PBKDF2_HMAC_SHA256,
        NonZeroU32::new(100000).unwrap(),
        &salt.as_ref()[..16],
        password.as_bytes(),
        &mut key,
    );
    STANDARD.encode(key)
}
fn key(encoded: &str) -> Result<aead::LessSafeKey, String> {
    let bytes = STANDARD.decode(encoded).map_err(|_| "密钥无效")?;
    Ok(aead::LessSafeKey::new(
        aead::UnboundKey::new(&aead::AES_256_GCM, &bytes).map_err(|_| "密钥无效")?,
    ))
}
pub fn seal(text: &str, encoded: &str) -> Result<String, String> {
    let mut nonce = [0u8; 12];
    SystemRandom::new()
        .fill(&mut nonce)
        .map_err(|_| "随机数不可用")?;
    let mut bytes = text.as_bytes().to_vec();
    key(encoded)?
        .seal_in_place_append_tag(
            aead::Nonce::assume_unique_for_key(nonce),
            aead::Aad::empty(),
            &mut bytes,
        )
        .map_err(|_| "加密失败")?;
    let mut output = nonce.to_vec();
    output.extend(bytes);
    Ok(STANDARD.encode(output))
}
pub fn open(text: &str, encoded: &str) -> Result<String, String> {
    let bytes = STANDARD.decode(text).map_err(|_| "加密格式无效")?;
    if bytes.len() < 28 {
        return Err("加密格式无效".into());
    }
    let mut data = bytes[12..].to_vec();
    let plain = key(encoded)?
        .open_in_place(
            aead::Nonce::try_assume_unique_for_key(&bytes[..12]).map_err(|_| "加密格式无效")?,
            aead::Aad::empty(),
            &mut data,
        )
        .map_err(|_| "加密密码不一致")?;
    String::from_utf8(plain.to_vec()).map_err(|_| "文本编码无效".into())
}
pub fn random_key() -> String {
    let mut b = [0u8; 32];
    SystemRandom::new().fill(&mut b).unwrap();
    STANDARD.encode(b)
}
pub fn random_id() -> String {
    let mut b = [0u8; 16];
    SystemRandom::new().fill(&mut b).unwrap();
    hash(&b)[..32].into()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn mobile_protocol_vector() {
        assert_eq!(
            open(
                "AAECAwQFBgcICQoLDv7L0NrdVkdC+ltn7/sFX4vg5WGuh4bQkgGbBb+qps5Osc3qiKfycWIUlJL3Zg==",
                &derive("cross-platform-password", "fixture-a")
            )
            .unwrap(),
            "Windows Mac 安卓 iPhone iPad"
        );
    }
    #[test]
    fn old_records_try_default_account_and_saved_keys() {
        use crate::{legacy, state::State};
        use serde_json::json;
        let state = State {
            username: "fixture-user".into(),
            key: derive("custom", "fixture-user"),
            ..State::default()
        };
        let mut keys = legacy::keys(&state);
        let account = legacy::account_key(
            &json!({"password": STANDARD.encode("%E5%AF%86%E7%A0%81%2Bfixture%20%25")}),
            &state.username,
        )
        .unwrap()
        .unwrap();
        assert_eq!(account, derive("密码+fixture %", "fixture-user"));
        legacy::add(&mut keys, account);
        for password in ["123456789", "custom", "密码+fixture %"] {
            let key = derive(password, &state.username);
            let item = json!({"content": seal("可见正文", &key).unwrap(), "imageUrl": seal("data:image/png;base64,AQID", &key).unwrap(), "encrypted": true});
            let plain = legacy::decrypt(item, &keys).unwrap();
            assert_eq!(plain["content"], "可见正文");
            assert_eq!(plain["imageUrl"], "data:image/png;base64,AQID");
            assert_eq!(plain["encrypted"], false);
        }
        let unknown = json!({"content": seal("old", &derive("unknown", &state.username)).unwrap(), "encrypted": true});
        assert!(legacy::decrypt(unknown, &keys).is_err());
        let meta = json!({"content":"", "encrypted":true, "metadataOnly":true});
        assert!(legacy::decrypt(meta, &keys).is_err());
        let plain = json!({"content":"already readable", "encrypted":false});
        assert_eq!(legacy::decrypt(plain.clone(), &keys).unwrap(), plain);
    }
    #[test]
    fn authenticated_encryption() {
        let k = derive("test-password", "fixture-a");
        let s = seal("中文 clipboard", &k).unwrap();
        assert_eq!(open(&s, &k).unwrap(), "中文 clipboard");
        assert_ne!(s, seal("中文 clipboard", &k).unwrap());
        assert!(open(&s, &derive("wrong", "fixture-a")).is_err());
        assert!(open("AA==", &k).is_err());
    }
}
