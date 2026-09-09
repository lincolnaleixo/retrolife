mod catalog;

use godot::builtin::{GString, PackedByteArray, PackedFloat32Array};
use godot::classes::Node;
use godot::prelude::*;
use retrolife_emulation::{
    EmulationEvent, EmulationRuntime, JOYPAD_A, JOYPAD_B, JOYPAD_DOWN, JOYPAD_L, JOYPAD_LEFT,
    JOYPAD_R, JOYPAD_RIGHT, JOYPAD_SELECT, JOYPAD_START, JOYPAD_UP, JOYPAD_X, JOYPAD_Y,
    RuntimeStatus, SessionInfo, StartRequest,
};
use serde::Serialize;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

const RESPONSE_SCHEMA_VERSION: u32 = 1;
const INPUT_PLAYER: usize = 0;
const AUDIO_DRAIN_FRAMES: usize = 2_048;

struct RetroLifeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RetroLifeExtension {}

struct BackendState {
    library_root: PathBuf,
    save_root: PathBuf,
    core_path: PathBuf,
    runtime: Option<EmulationRuntime>,
    session_serial: u64,
    session_id: String,
    game_id: String,
    last_frame_sequence: u64,
    last_frame_width: u32,
    last_frame_height: u32,
    input_mask: u16,
    session_info: Option<SessionInfo>,
    last_error: Option<String>,
}

impl Default for BackendState {
    fn default() -> Self {
        let root = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        Self {
            library_root: root.join(".cache").join("library"),
            save_root: root.join(".cache").join("saves"),
            core_path: root
                .join("frontend")
                .join("godot-ui")
                .join("bin")
                .join("bsnes-jg_libretro.so"),
            runtime: None,
            session_serial: 0,
            session_id: String::new(),
            game_id: String::new(),
            last_frame_sequence: 0,
            last_frame_width: 0,
            last_frame_height: 0,
            input_mask: 0,
            session_info: None,
            last_error: None,
        }
    }
}

impl BackendState {
    fn clear_session(&mut self) {
        self.session_id.clear();
        self.game_id.clear();
        self.last_frame_sequence = 0;
        self.last_frame_width = 0;
        self.last_frame_height = 0;
        self.input_mask = 0;
        self.session_info = None;
    }
}

#[derive(GodotClass)]
#[class(init, base=Node)]
struct RetroLifeBackend {
    base: Base<Node>,
    state: Mutex<BackendState>,
}

impl RetroLifeBackend {
    fn state(&self) -> Result<std::sync::MutexGuard<'_, BackendState>, String> {
        self.state
            .lock()
            .map_err(|_| "The Rust bridge state is unavailable.".to_owned())
    }

    fn configured_paths(&self) -> Result<(PathBuf, PathBuf, PathBuf), String> {
        let state = self.state()?;
        Ok((
            state.library_root.clone(),
            state.save_root.clone(),
            state.core_path.clone(),
        ))
    }

    fn poll_events(state: &mut BackendState) {
        let events = state
            .runtime
            .as_ref()
            .map(EmulationRuntime::drain_events)
            .unwrap_or_default();
        for event in events {
            match event {
                EmulationEvent::Started(info) => {
                    state.session_info = Some(info);
                    state.last_error = None;
                }
                EmulationEvent::Failed { message } => {
                    state.last_error = Some(message);
                }
                EmulationEvent::Stopped { .. } => state.clear_session(),
                EmulationEvent::Starting | EmulationEvent::Paused | EmulationEvent::Resumed => {}
            }
        }
        if let Some(runtime) = state.runtime.as_ref()
            && let Some(error) = runtime.snapshot().last_error
        {
            state.last_error = Some(error);
        }
    }

    fn runtime_status(state: &BackendState) -> &'static str {
        match state
            .runtime
            .as_ref()
            .map(|runtime| runtime.snapshot().status)
        {
            Some(RuntimeStatus::Starting) => "starting",
            Some(RuntimeStatus::Running) => "running",
            Some(RuntimeStatus::Paused) => "paused",
            Some(RuntimeStatus::Stopping) => "stopping",
            Some(RuntimeStatus::Failed) => "failed",
            Some(RuntimeStatus::Stopped) | None => "stopped",
        }
    }
}

#[godot_api]
impl RetroLifeBackend {
    #[func]
    fn ping(&self) -> GString {
        let message = format!(
            "RetroLife Rust bridge connected to core {}",
            retrolife_core::version()
        );
        GString::from(message.as_str())
    }

    #[func]
    fn core_version(&self) -> GString {
        GString::from(retrolife_core::version())
    }

    #[func]
    fn default_display_settings_json(&self) -> GString {
        let json = retrolife_core::default_display_settings_json();
        GString::from(json.as_str())
    }

    /// Configure paths supplied by Godot's platform-aware user-data and
    /// bundle helpers. Absolute paths are kept in memory only and never
    /// returned in bridge responses.
    #[func]
    fn configure_paths_json(
        &self,
        library_root: GString,
        save_root: GString,
        core_path: GString,
    ) -> GString {
        let result = (|| {
            let library_root = checked_path(library_root.to_string(), "library root")?;
            let save_root = checked_path(save_root.to_string(), "save root")?;
            let core_path = checked_path(core_path.to_string(), "core path")?;
            let mut state = self.state()?;
            if state.runtime.is_some() {
                return Err("Stop the active emulation session before changing paths.".to_owned());
            }
            retrolife_library::Library::open(&library_root).map_err(|error| error.to_string())?;
            state.library_root = library_root;
            state.save_root = save_root;
            state.core_path = core_path;
            Ok(SimpleAck { configured: true })
        })();
        GString::from(response_json(result).as_str())
    }

    #[func]
    fn library_status_json(&self) -> GString {
        let result = self
            .configured_paths()
            .map(|(library_root, _, _)| catalog::status_json(&library_root));
        let json = match result {
            Ok(json) => json,
            Err(error) => error_json(error),
        };
        GString::from(json.as_str())
    }

    #[func]
    fn library_view_json(
        &self,
        system_id: GString,
        search: GString,
        offset: i64,
        limit: i64,
    ) -> GString {
        let result = self.configured_paths().map(|(library_root, _, _)| {
            catalog::view_json(
                &library_root,
                &system_id.to_string(),
                &search.to_string(),
                offset,
                limit,
            )
        });
        let json = match result {
            Ok(json) => json,
            Err(error) => error_json(error),
        };
        GString::from(json.as_str())
    }

    #[func]
    fn library_game_details_json(&self, game_id: GString) -> GString {
        let result = self
            .configured_paths()
            .map(|(library_root, _, _)| catalog::details_json(&library_root, &game_id.to_string()));
        let json = match result {
            Ok(json) => json,
            Err(error) => error_json(error),
        };
        GString::from(json.as_str())
    }

    #[func]
    fn library_import_json(&self, source_path: GString) -> GString {
        let result = self.configured_paths().map(|(library_root, _, _)| {
            catalog::import_json(&library_root, Path::new(&source_path.to_string()))
        });
        let json = match result {
            Ok(json) => json,
            Err(error) => error_json(error),
        };
        GString::from(json.as_str())
    }

    // Compatibility aliases intentionally target the local store. There is
    // no reference catalog or server snapshot fallback in this extension.
    #[func]
    fn catalog_status_json(&self) -> GString {
        self.library_status_json()
    }

    #[func]
    fn catalog_view_json(
        &self,
        system_id: GString,
        search: GString,
        offset: i64,
        limit: i64,
    ) -> GString {
        self.library_view_json(system_id, search, offset, limit)
    }

    #[func]
    fn game_details_json(&self, game_id: GString) -> GString {
        self.library_game_details_json(game_id)
    }

    #[func]
    fn start_emulation_json(&self, game_id: GString) -> GString {
        let result = (|| {
            let game_id = checked_identifier(game_id.to_string(), "game id")?;
            let (library_root, save_root, core_path) = self.configured_paths()?;
            let (_, content_path) = catalog::entry(&library_root, &game_id)?;
            let mut state = self.state()?;
            if state.runtime.is_none() {
                state.runtime = Some(EmulationRuntime::new().map_err(|error| error.to_string())?);
            }
            let request =
                StartRequest::new(core_path, content_path, save_root, "snes", game_id.clone());
            state
                .runtime
                .as_ref()
                .ok_or_else(|| "The emulator worker is unavailable.".to_owned())?
                .start(request)
                .map_err(|error| error.to_string())?;
            state.session_serial = state.session_serial.saturating_add(1);
            state.session_id = format!("session-{}", state.session_serial);
            state.game_id = game_id;
            state.last_frame_sequence = 0;
            state.last_frame_width = 0;
            state.last_frame_height = 0;
            state.input_mask = 0;
            state.session_info = None;
            state.last_error = None;
            Ok(StartAck {
                session_id: state.session_id.clone(),
                status: "starting",
                video_width: None,
                video_height: None,
                sample_rate: None,
            })
        })();
        GString::from(response_json(result).as_str())
    }

    #[func]
    fn emulation_frame_rgba(&self) -> PackedByteArray {
        let Ok(mut state) = self.state() else {
            return PackedByteArray::new();
        };
        Self::poll_events(&mut state);
        let Some(runtime) = state.runtime.as_ref() else {
            return PackedByteArray::new();
        };
        let Some(frame) = runtime.video_frame_after(state.last_frame_sequence) else {
            return PackedByteArray::new();
        };
        state.last_frame_sequence = frame.info.sequence;
        state.last_frame_width = frame.info.width;
        state.last_frame_height = frame.info.height;
        PackedByteArray::from(frame.rgba)
    }

    #[func]
    fn emulation_advance_frame_json(&self) -> GString {
        let result = (|| {
            let state = self.state()?;
            state
                .runtime
                .as_ref()
                .ok_or_else(|| "No emulation session is active.".to_owned())?
                .run_frame()
                .map_err(|error| error.to_string())?;
            Ok(SimpleAck { configured: true })
        })();
        GString::from(response_json(result).as_str())
    }

    #[func]
    fn emulation_frame_info_json(&self) -> GString {
        let result = (|| {
            let state = self.state()?;
            if state.last_frame_sequence == 0 {
                return Err("No video frame is available yet.".to_owned());
            }
            Ok(FrameInfoDto {
                width: state.last_frame_width,
                height: state.last_frame_height,
                sequence: state.last_frame_sequence,
                fps: state.session_info.as_ref().map(|info| info.fps),
                sample_rate: state.session_info.as_ref().map(|info| info.sample_rate),
                aspect_ratio: state.session_info.as_ref().map(|info| info.aspect_ratio),
            })
        })();
        GString::from(response_json(result).as_str())
    }

    #[func]
    fn emulation_audio_samples_available(&self, max_frames: i64) -> PackedFloat32Array {
        let max_frames = usize::try_from(max_frames).unwrap_or(0);
        self.drain_audio_samples(max_frames.min(AUDIO_DRAIN_FRAMES))
    }

    #[func]
    fn emulation_audio_samples(&self) -> PackedFloat32Array {
        self.drain_audio_samples(AUDIO_DRAIN_FRAMES)
    }

    fn drain_audio_samples(&self, max_frames: usize) -> PackedFloat32Array {
        let Ok(state) = self.state() else {
            return PackedFloat32Array::new();
        };
        let Some(runtime) = state.runtime.as_ref() else {
            return PackedFloat32Array::new();
        };
        let samples = runtime.drain_audio(max_frames);
        PackedFloat32Array::from(
            samples
                .into_iter()
                .map(|sample| f32::from(sample) / 32_768.0)
                .collect::<Vec<_>>(),
        )
    }

    #[func]
    fn set_emulation_input_json(&self, action: GString, pressed: bool) -> GString {
        let result = (|| {
            let mut state = self.state()?;
            let bit = action_bit(&action.to_string())
                .ok_or_else(|| "Unknown SNES input action.".to_owned())?;
            if pressed {
                state.input_mask |= bit;
            } else {
                state.input_mask &= !bit;
            }
            state
                .runtime
                .as_ref()
                .ok_or_else(|| "No emulation session is active.".to_owned())?
                .set_input(INPUT_PLAYER, state.input_mask)
                .map_err(|error| error.to_string())?;
            Ok(SimpleAck { configured: true })
        })();
        GString::from(response_json(result).as_str())
    }

    #[func]
    fn pause_emulation_json(&self) -> GString {
        GString::from(self.set_paused(true).as_str())
    }

    #[func]
    fn resume_emulation_json(&self) -> GString {
        GString::from(self.set_paused(false).as_str())
    }

    #[func]
    fn reset_emulation_json(&self) -> GString {
        let result = self
            .state()
            .and_then(|state| {
                state
                    .runtime
                    .as_ref()
                    .ok_or_else(|| "No emulation session is active.".to_owned())?
                    .reset()
                    .map_err(|error| error.to_string())
            })
            .map(|_| SimpleAck { configured: true });
        GString::from(response_json(result).as_str())
    }

    #[func]
    fn stop_emulation_json(&self) -> GString {
        let result = (|| {
            let mut state = self.state()?;
            let Some(runtime) = state.runtime.as_ref() else {
                state.clear_session();
                return Ok(SimpleAck { configured: true });
            };
            runtime.stop().map_err(|error| error.to_string())?;
            Ok(SimpleAck { configured: true })
        })();
        GString::from(response_json(result).as_str())
    }

    #[func]
    fn emulation_status_json(&self) -> GString {
        let result = (|| {
            let mut state = self.state()?;
            Self::poll_events(&mut state);
            let snapshot = state.runtime.as_ref().map(EmulationRuntime::snapshot);
            Ok(StatusDto {
                status: Self::runtime_status(&state),
                session_id: state.session_id.clone(),
                game_id: state.game_id.clone(),
                video_width: state.session_info.as_ref().map(|info| info.width),
                video_height: state.session_info.as_ref().map(|info| info.height),
                sample_rate: state.session_info.as_ref().map(|info| info.sample_rate),
                fps: state.session_info.as_ref().map(|info| info.fps),
                frame_sequence: snapshot
                    .as_ref()
                    .map(|value| value.frame_sequence)
                    .unwrap_or(0),
                aspect_ratio: state.session_info.as_ref().map(|info| info.aspect_ratio),
                last_error: state.last_error.clone(),
            })
        })();
        GString::from(response_json(result).as_str())
    }

    fn set_paused(&self, paused: bool) -> String {
        let result = self
            .state()
            .and_then(|state| {
                state
                    .runtime
                    .as_ref()
                    .ok_or_else(|| "No emulation session is active.".to_owned())?
                    .set_paused(paused)
                    .map_err(|error| error.to_string())
            })
            .map(|_| SimpleAck { configured: true });
        response_json(result)
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SimpleAck {
    configured: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct StartAck {
    session_id: String,
    status: &'static str,
    video_width: Option<u32>,
    video_height: Option<u32>,
    sample_rate: Option<f64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct FrameInfoDto {
    width: u32,
    height: u32,
    sequence: u64,
    fps: Option<f64>,
    sample_rate: Option<f64>,
    aspect_ratio: Option<f32>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct StatusDto {
    status: &'static str,
    session_id: String,
    game_id: String,
    video_width: Option<u32>,
    video_height: Option<u32>,
    sample_rate: Option<f64>,
    fps: Option<f64>,
    aspect_ratio: Option<f32>,
    frame_sequence: u64,
    last_error: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BridgeResponse<T: Serialize> {
    schema_version: u32,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn response_json<T: Serialize>(result: Result<T, String>) -> String {
    let response = match result {
        Ok(data) => BridgeResponse {
            schema_version: RESPONSE_SCHEMA_VERSION,
            ok: true,
            data: Some(data),
            error: None,
        },
        Err(error) => BridgeResponse::<T> {
            schema_version: RESPONSE_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error),
        },
    };
    serde_json::to_string(&response).unwrap_or_else(|_| {
        r#"{"schemaVersion":1,"ok":false,"error":"The bridge could not encode its response."}"#
            .to_owned()
    })
}

fn error_json(error: String) -> String {
    response_json::<()>(Err(error))
}

fn checked_path(value: String, label: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(value.trim());
    if path.as_os_str().is_empty() {
        return Err(format!("{label} must not be empty."));
    }
    if path.as_os_str().to_string_lossy().contains('\0') {
        return Err(format!("{label} contains an invalid character."));
    }
    Ok(path)
}

fn checked_identifier(value: String, label: &str) -> Result<String, String> {
    let value = value.trim().to_owned();
    if value.is_empty() || value.len() > 128 || value == "." || value == ".." {
        return Err(format!("{label} is invalid."));
    }
    if value.contains('/') || value.contains('\\') || value.as_bytes().contains(&0) {
        return Err(format!("{label} is invalid."));
    }
    Ok(value)
}

fn action_bit(action: &str) -> Option<u16> {
    match action.trim().to_ascii_lowercase().as_str() {
        "up" => Some(JOYPAD_UP),
        "down" => Some(JOYPAD_DOWN),
        "left" => Some(JOYPAD_LEFT),
        "right" => Some(JOYPAD_RIGHT),
        // Logical directions follow the physical diamond: south is the
        // bottom button (SNES B), east is the right button (SNES A), west is
        // the left button (SNES Y), and north is the top button (SNES X).
        "south" | "b" => Some(JOYPAD_B),
        "east" | "a" => Some(JOYPAD_A),
        "west" | "y" => Some(JOYPAD_Y),
        "north" | "x" => Some(JOYPAD_X),
        "start" => Some(JOYPAD_START),
        "select" => Some(JOYPAD_SELECT),
        "leftshoulder" | "left_shoulder" | "l" => Some(JOYPAD_L),
        "rightshoulder" | "right_shoulder" | "r" => Some(JOYPAD_R),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn physical_snes_actions_map_to_the_expected_bits() {
        let expected = [
            ("up", JOYPAD_UP),
            ("down", JOYPAD_DOWN),
            ("left", JOYPAD_LEFT),
            ("right", JOYPAD_RIGHT),
            ("south", JOYPAD_B),
            ("east", JOYPAD_A),
            ("west", JOYPAD_Y),
            ("north", JOYPAD_X),
            ("left_shoulder", JOYPAD_L),
            ("right_shoulder", JOYPAD_R),
            ("start", JOYPAD_START),
            ("select", JOYPAD_SELECT),
        ];

        for (action, bit) in expected {
            assert_eq!(
                action_bit(action),
                Some(bit),
                "unexpected mapping for {action}"
            );
        }
    }

    #[test]
    fn physical_snes_aliases_are_case_and_separator_tolerant() {
        assert_eq!(action_bit("B"), Some(JOYPAD_B));
        assert_eq!(action_bit("a"), Some(JOYPAD_A));
        assert_eq!(action_bit("Y"), Some(JOYPAD_Y));
        assert_eq!(action_bit("x"), Some(JOYPAD_X));
        assert_eq!(action_bit("leftshoulder"), Some(JOYPAD_L));
        assert_eq!(action_bit("rightshoulder"), Some(JOYPAD_R));
        assert_eq!(action_bit("unknown"), None);
    }
}
