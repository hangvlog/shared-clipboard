use serde_json::Value;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
unsafe extern "C" {
    fn native_clipboard_reset();
    pub fn native_run() -> c_int;
    fn native_status(text: *const c_char);
    fn native_request(
        method: *const c_char,
        url: *const c_char,
        token: *const c_char,
        body: *const c_char,
        status: *mut c_int,
    ) -> *mut c_char;
    fn native_ws_open(url: *const c_char, generation: u64);
    fn native_ws_send(text: *const c_char);
    fn native_ws_close();
    fn native_data_dir() -> *mut c_char;
    fn native_secret_load() -> *mut c_char;
    fn native_secret_save(text: *const c_char) -> c_int;
    fn native_clipboard_text() -> *mut c_char;
    fn native_clipboard_png(length: *mut usize) -> *mut u8;
    fn native_clipboard_write(text: *const c_char, image: *const u8, length: usize) -> c_int;
    fn native_free(ptr: *mut c_void);
    fn native_history_begin();
    fn native_history_item(id: *const c_char, text: *const c_char);
    fn native_history_end();
    fn native_detail(
        id: *const c_char,
        text: *const c_char,
        image: *const u8,
        length: usize,
        success: c_int,
    );
    fn native_session(logged_in: c_int);
}
fn c(s: &str) -> CString {
    CString::new(s.replace('\0', "")).unwrap()
}
unsafe fn take(p: *mut c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    let s = CStr::from_ptr(p).to_string_lossy().into_owned();
    native_free(p.cast());
    s
}
pub fn status(s: &str) {
    unsafe { native_status(c(s).as_ptr()) }
}
pub fn request(method: &str, url: &str, token: &str, body: &Value) -> Result<Value, String> {
    let mut code = 0;
    let b = if body.is_null() {
        String::new()
    } else {
        body.to_string()
    };
    let raw = unsafe {
        take(native_request(
            c(method).as_ptr(),
            c(url).as_ptr(),
            c(token).as_ptr(),
            c(&b).as_ptr(),
            &mut code,
        ))
    };
    if code == 401 {
        return Err("登录已过期，请重新登录".into());
    }
    if !(200..300).contains(&code) {
        return Err(format!("网络请求失败（{code}）"));
    }
    let v: Value = serde_json::from_str(&raw).map_err(|_| "服务器响应无效")?;
    if v["code"] == 1 || v["code"] == 200 {
        Ok(v["data"].clone())
    } else {
        Err("服务器拒绝请求".into())
    }
}
pub fn ws_open(url: &str, generation: u64) {
    unsafe { native_ws_open(c(url).as_ptr(), generation) }
}
pub fn ws_send(text: &str) {
    unsafe { native_ws_send(c(text).as_ptr()) }
}
pub fn ws_close() {
    unsafe { native_ws_close() }
}
pub fn load() -> String {
    unsafe { take(native_secret_load()) }
}
pub fn save(text: &str) -> Result<(), String> {
    if unsafe { native_secret_save(c(text).as_ptr()) } != 0 {
        Ok(())
    } else {
        Err("系统安全存储不可用".into())
    }
}
pub fn clipboard() -> Result<(String, Vec<u8>), String> {
    unsafe {
        let text = take(native_clipboard_text());
        let mut len = 0;
        let p = native_clipboard_png(&mut len);
        if len == usize::MAX {
            return Err("图片过大或格式不支持".into());
        }
        let image = if p.is_null() {
            vec![]
        } else {
            let b = std::slice::from_raw_parts(p, len).to_vec();
            native_free(p.cast());
            b
        };
        Ok((text, image))
    }
}
pub fn write(text: &str, image: &[u8]) -> Result<(), String> {
    if unsafe { native_clipboard_write(c(text).as_ptr(), image.as_ptr(), image.len()) } != 0 {
        Ok(())
    } else {
        Err("无法写入剪贴板".into())
    }
}
pub fn history(rows: &[(String, String)]) {
    unsafe {
        native_history_begin();
        for (id, s) in rows {
            native_history_item(c(id).as_ptr(), c(s).as_ptr())
        }
        native_history_end();
    }
}

pub fn data_dir() -> Result<std::path::PathBuf, String> {
    let path = unsafe { take(native_data_dir()) };
    if path.is_empty() {
        Err("本地目录不可用".into())
    } else {
        Ok(path.into())
    }
}

pub fn reset_clipboard() {
    unsafe {
        native_clipboard_reset();
    }
}

pub fn detail(id: &str, text: &str, image: &[u8], success: bool) {
    unsafe {
        native_detail(
            c(id).as_ptr(),
            c(text).as_ptr(),
            image.as_ptr(),
            image.len(),
            success as c_int,
        );
    }
}

pub fn session(logged_in: bool) {
    unsafe {
        native_session(logged_in as c_int);
    }
}
