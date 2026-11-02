//! Command-line session control for scripts and remote administration:
//! `login <account>` (password on stdin), `status`, `logout`. The running app adopts the change.
use crate::{
    platform,
    session::{self, Http, Native},
    state::State,
};
use serde_json::json;
use std::io::{BufRead, Write};

const USAGE: &str = "用法: shared-clipboard login <账号>   # 从标准输入读取登录密码\n       shared-clipboard status\n       shared-clipboard logout";

/// `None` when started without a command, i.e. as the desktop app.
pub fn run(args: &[String]) -> Option<i32> {
    let command = args.first()?.as_str();
    if !matches!(command, "login" | "status" | "logout" | "help" | "--help" | "-h") {
        return None;
    }
    platform::attach_console();
    let result = match command {
        "login" => match args.get(1) {
            Some(account) => login(account, &read_password()),
            None => Err(USAGE.into()),
        },
        "status" => Ok(status(&State::load())),
        "logout" => logout(),
        "help" | "--help" | "-h" => Ok(json!({"usage": USAGE})),
        _ => return None,
    };
    let (code, value) = match result {
        Ok(value) => (0, value),
        Err(e) => (1, json!({"ok": false, "error": e})),
    };
    let mut out = std::io::stdout();
    let _ = writeln!(out, "{value}");
    let _ = out.flush();
    Some(code)
}

fn read_password() -> String {
    let mut line = String::new();
    let _ = std::io::stdin().lock().read_line(&mut line);
    password_line(&line)
}

/// PowerShell on a UTF-8 console prefixes piped input with a byte-order mark.
fn password_line(raw: &str) -> String {
    raw.trim_start_matches('\u{feff}')
        .trim_end_matches(['\r', '\n'])
        .to_string()
}

fn login(account: &str, password: &str) -> Result<serde_json::Value, String> {
    let mut state = State::load();
    sign_in(&Native, &mut state, account, password)?;
    state.save()?;
    platform::announce_session();
    Ok(status(&state))
}

/// Exchange the password for a renewable session and revoke the one it replaces.
fn sign_in(http: &dyn Http, state: &mut State, account: &str, password: &str) -> Result<(), String> {
    if account.trim().is_empty() || password.is_empty() {
        return Err("请提供账号，并从标准输入提供登录密码".into());
    }
    let grant = session::login(http, account.trim(), password, &state.device, session::now())?;
    let previous = state.sign_in(grant, None);
    session::logout(http, &previous, &state.device);
    Ok(())
}

fn logout() -> Result<serde_json::Value, String> {
    let mut state = State::load();
    let previous = state.sign_out();
    state.save()?;
    session::logout(&Native, &previous, &state.device);
    platform::announce_session();
    Ok(status(&state))
}

fn status(state: &State) -> serde_json::Value {
    json!({
        "ok": true,
        "signed_in": !state.token.is_empty(),
        "username": state.username,
        "renewable": !state.refresh_token.is_empty(),
        "expires_in": state.expires_at.saturating_sub(session::now()),
    })
}

#[cfg(test)]
#[path = "cli_tests.rs"]
mod tests;
