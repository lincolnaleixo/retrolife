//! Optional macOS Sparkle boundary. No game data, credentials or URL arguments
//! cross this ABI. The loaded library lives for the process because AppKit owns
//! callbacks into it. All public entrypoints are called on Godot's main thread.
use serde_json::{Value, json};

const COMMANDS: &[&str] = &[
    "status",
    "check",
    "checks_on",
    "checks_off",
    "downloads_on",
    "downloads_off",
    "beta_on",
    "beta_off",
];

pub fn command(command: &str) -> String {
    if !COMMANDS.contains(&command) {
        return json!({"schemaVersion":1,"ok":false,"error":"Unknown updater command."}).to_string();
    }
    native_command(command).to_string()
}

pub fn begin_game() -> Result<(), String> {
    let response = native_command("game_begin");
    if response.get("ok").and_then(Value::as_bool) == Some(true) {
        Ok(())
    } else {
        Err(response["error"]
            .as_str()
            .unwrap_or("Finish the current update before starting a game.")
            .to_owned())
    }
}

pub fn end_game() {
    let _ = native_command("game_end");
}

fn unavailable(command: &str) -> Value {
    let message = "Updates are available in installed, signed macOS releases. Development and Linux builds do not replace themselves.";
    let allowed = matches!(command, "status" | "game_begin" | "game_end");
    json!({"schemaVersion":1,"ok":allowed,"error": if allowed {None} else {Some(message)},
        "data":{"available":false,"state":"unavailable","message":message,
        "currentVersion":env!("CARGO_PKG_VERSION"),"availableVersion":"","canCheck":false,
        "automaticChecks":false,"automaticDownloads":false,"includeBeta":false,
        "sessionInProgress":false,"gameActive":false,"installPending":false,"lastChecked":0}})
}

#[cfg(not(target_os = "macos"))]
fn native_command(command: &str) -> Value {
    unavailable(command)
}

#[cfg(target_os = "macos")]
fn native_command(command: &str) -> Value {
    use libloading::Library;
    use std::ffi::{CStr, CString, c_char};
    use std::sync::OnceLock;
    type Call = unsafe extern "C" fn(*const c_char) -> *mut c_char;
    type Free = unsafe extern "C" fn(*mut c_char);
    struct Native {
        _library: Library,
        call: Call,
        free: Free,
    }
    static NATIVE: OnceLock<Option<Native>> = OnceLock::new();
    let native = NATIVE.get_or_init(|| {
        let executable = std::env::current_exe().ok()?;
        let macos = executable.parent()?;
        if macos.file_name()? != "MacOS" {
            return None;
        }
        let path = macos.parent()?.join("Frameworks/libretrolife_updater.dylib");
        // Only the containing application's signed Frameworks directory. Never
        // search the working directory, PATH or caller-provided locations.
        let library = unsafe { Library::new(path) }.ok()?;
        let call = unsafe { *library.get::<Call>(b"rl_updater_command\0").ok()? };
        let free = unsafe { *library.get::<Free>(b"rl_updater_free\0").ok()? };
        Some(Native {
            _library: library,
            call,
            free,
        })
    });
    let Some(native) = native else {
        return unavailable(command);
    };
    let Ok(input) = CString::new(command) else {
        return json!({"schemaVersion":1,"ok":false,"error":"Invalid updater command."});
    };
    // Native allocation is copied and freed before another call or callback.
    let pointer = unsafe { (native.call)(input.as_ptr()) };
    if pointer.is_null() {
        return json!({"schemaVersion":1,"ok":false,"error":"Updater allocation failed."});
    }
    let parsed = unsafe { serde_json::from_slice::<Value>(CStr::from_ptr(pointer).to_bytes()) };
    unsafe { (native.free)(pointer) };
    match parsed {
        Ok(value) if value["schemaVersion"] == 1 && value["ok"].is_boolean() => value,
        _ => json!({"schemaVersion":1,"ok":false,"error":"Invalid native updater response."}),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn public_commands_cannot_clear_the_game_guard_or_set_a_feed() {
        for name in ["game_end", "game_begin", "set_url", "status\0check", "", "CHECK"] {
            let data: Value = serde_json::from_str(&command(name)).unwrap();
            assert_eq!(data["ok"], false);
        }
    }
    #[test]
    fn unsupported_build_is_explicit_and_never_blocks_games() {
        assert_eq!(unavailable("status")["data"]["available"], false);
        assert_eq!(unavailable("check")["ok"], false);
        assert_eq!(unavailable("game_begin")["ok"], true);
        assert_eq!(unavailable("game_end")["ok"], true);
    }
}
