#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]
mod crypto;
mod engine;
mod events;
mod legacy;
mod platform;
mod state;
mod telemetry;
use std::{
    ffi::{c_char, CStr},
    sync::Once,
};
#[no_mangle]
pub extern "C" fn sc_start() {
    static START: Once = Once::new();
    START.call_once(|| {
        telemetry::started();
        std::thread::Builder::new()
            .name("clipboard-sync".into())
            .spawn(engine::run)
            .unwrap();
    });
}
#[no_mangle]
pub unsafe extern "C" fn sc_event(kind: i32, data: *const c_char) {
    let s = if data.is_null() {
        String::new()
    } else {
        CStr::from_ptr(data).to_string_lossy().into_owned()
    };
    events::send(kind, s);
}
#[no_mangle]
pub unsafe extern "C" fn sc_login(
    user: *const c_char,
    password: *const c_char,
    encryption: *const c_char,
) {
    let value = serde_json::json!({"username":CStr::from_ptr(user).to_string_lossy(),"password":CStr::from_ptr(password).to_string_lossy(),"encryption":CStr::from_ptr(encryption).to_string_lossy()});
    events::send(1, value.to_string());
}
#[no_mangle]
pub extern "C" fn sc_history_select(index: i32) {
    events::send(6, index.to_string());
}
fn main() {
    unsafe {
        platform::native_run();
    }
}

#[cfg(test)]
mod network_tests;
