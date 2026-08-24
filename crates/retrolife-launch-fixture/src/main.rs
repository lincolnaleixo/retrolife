use serde_json::json;
use std::{collections::BTreeMap, env, fs, path::Path, process, thread, time::Duration};

fn main() {
    match run() {
        Ok(exit_code) => process::exit(exit_code),
        Err(error) => {
            eprintln!("RETROLIFE_LAUNCH_FIXTURE_ERROR {error}");
            process::exit(111);
        }
    }
}

fn run() -> Result<i32, String> {
    let arguments = parse_arguments()?;
    let game_id = required(&arguments, "game-id")?;
    let content_path = required(&arguments, "content")?;
    let save_directory = required(&arguments, "save-dir")?;
    let session_directory = required(&arguments, "session-dir")?;
    let input_profile_path = required(&arguments, "input-profile")?;
    let sleep_ms = optional_number(&arguments, "sleep-ms", 40)?;
    let exit_code = optional_number(&arguments, "exit-code", 0)? as i32;

    if !Path::new(content_path).is_file() {
        return Err(format!("content file does not exist: {content_path}"));
    }
    if !Path::new(input_profile_path).is_file() {
        return Err(format!(
            "materialized input profile does not exist: {input_profile_path}"
        ));
    }
    fs::create_dir_all(save_directory)
        .map_err(|error| format!("cannot create save directory: {error}"))?;
    fs::create_dir_all(session_directory)
        .map_err(|error| format!("cannot create session directory: {error}"))?;

    let profile_text = fs::read_to_string(input_profile_path)
        .map_err(|error| format!("cannot read input profile: {error}"))?;
    let profile_json: serde_json::Value = serde_json::from_str(&profile_text)
        .map_err(|error| format!("input profile is not valid JSON: {error}"))?;
    let profile_count = profile_json
        .get("profiles")
        .and_then(serde_json::Value::as_array)
        .map(Vec::len)
        .unwrap_or(0);
    if profile_count == 0 {
        return Err("input profile bundle contains no profiles".to_owned());
    }

    let observed_path = Path::new(session_directory).join("observed-launch.json");
    let observed = json!({
        "schemaVersion": 1,
        "gameId": game_id,
        "contentPath": content_path,
        "saveDirectory": save_directory,
        "sessionDirectory": session_directory,
        "inputProfilePath": input_profile_path,
        "inputProfileCount": profile_count,
        "environmentGameId": env::var("RETROLIFE_GAME_ID").unwrap_or_default(),
        "environmentSystemId": env::var("RETROLIFE_SYSTEM_ID").unwrap_or_default(),
        "workingDirectory": env::current_dir()
            .map(|path| path.to_string_lossy().into_owned())
            .unwrap_or_default(),
        "requestedExitCode": exit_code,
        "requestedSleepMs": sleep_ms,
    });
    fs::write(
        &observed_path,
        serde_json::to_vec_pretty(&observed)
            .map_err(|error| format!("cannot encode observed launch: {error}"))?,
    )
    .map_err(|error| format!("cannot write observed launch: {error}"))?;

    println!("RETROLIFE_LAUNCH_FIXTURE_STARTED game={game_id} profiles={profile_count}");
    if sleep_ms > 0 {
        thread::sleep(Duration::from_millis(sleep_ms));
    }
    println!("RETROLIFE_LAUNCH_FIXTURE_FINISHED exit={exit_code}");
    Ok(exit_code)
}

fn parse_arguments() -> Result<BTreeMap<String, String>, String> {
    let mut values = BTreeMap::new();
    let mut arguments = env::args().skip(1);
    while let Some(argument) = arguments.next() {
        let key = argument
            .strip_prefix("--")
            .ok_or_else(|| format!("unexpected positional argument {argument}"))?;
        let value = arguments
            .next()
            .ok_or_else(|| format!("argument --{key} requires a value"))?;
        if values.insert(key.to_owned(), value).is_some() {
            return Err(format!("argument --{key} was provided more than once"));
        }
    }
    Ok(values)
}

fn required<'a>(arguments: &'a BTreeMap<String, String>, key: &str) -> Result<&'a str, String> {
    arguments
        .get(key)
        .map(String::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("required argument --{key} is missing"))
}

fn optional_number(
    arguments: &BTreeMap<String, String>,
    key: &str,
    default: u64,
) -> Result<u64, String> {
    match arguments.get(key) {
        Some(value) => value
            .parse::<u64>()
            .map_err(|error| format!("argument --{key} is invalid: {error}")),
        None => Ok(default),
    }
}
