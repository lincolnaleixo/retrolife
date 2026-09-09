//! A bounded, in-process libretro session for RetroLife frontends.
//!
//! The crate owns the emulation lifecycle and transport boundary. A frontend
//! supplies a core shared library and game file, submits player masks, and
//! consumes the latest RGBA frame and bounded stereo sample queue. Presentation
//! concerns such as textures, audio devices, windowing, and input mapping stay
//! outside this crate.
//!
//! Supported cores must accept memory-backed content and return from every
//! libretro callback. Because the core runs in-process, the worker cannot
//! safely interrupt a callback that hangs.

mod libretro;
mod persistence;
mod transport;

use libretro::CoreSession;
use std::collections::{BTreeMap, VecDeque};
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use thiserror::Error;
use transport::{AtomicInputs, AudioRing, VideoSlot};

const COMMAND_CAPACITY: usize = 64;
const EVENT_CAPACITY: usize = 64;

fn send_shutdown(tx: &SyncSender<WorkerCommand>) -> Result<(), EmulationError> {
    tx.send(WorkerCommand::Shutdown)
        .map_err(|_| EmulationError::WorkerUnavailable)
}

/// A request to load one content file into one libretro core.
#[derive(Debug, Clone)]
pub struct StartRequest {
    /// Path to a libretro shared library (`.dylib`, `.so`, or platform equivalent).
    pub core_path: PathBuf,
    /// Path to the ROM or other content file accepted by the core.
    pub content_path: PathBuf,
    /// Root directory under which this session's battery file is stored.
    pub save_root: PathBuf,
    /// Stable system identifier used as the first save directory component.
    pub system_id: String,
    /// Stable game identifier used as the second save directory component.
    pub game_id: String,
    /// Core options keyed by their libretro option names.
    pub core_options: BTreeMap<String, String>,
}

impl StartRequest {
    /// Construct a request with no core option overrides.
    pub fn new(
        core_path: impl Into<PathBuf>,
        content_path: impl Into<PathBuf>,
        save_root: impl Into<PathBuf>,
        system_id: impl Into<String>,
        game_id: impl Into<String>,
    ) -> Self {
        Self {
            core_path: core_path.into(),
            content_path: content_path.into(),
            save_root: save_root.into(),
            system_id: system_id.into(),
            game_id: game_id.into(),
            core_options: BTreeMap::new(),
        }
    }

    /// Add or replace one frontend-selected core option.
    pub fn with_core_option(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.core_options.insert(key.into(), value.into());
        self
    }

    pub(crate) fn validate(&self) -> Result<(), EmulationError> {
        if self.core_path.as_os_str().is_empty() {
            return Err(EmulationError::InvalidRequest(
                "core path must not be empty".into(),
            ));
        }
        if self.content_path.as_os_str().is_empty() {
            return Err(EmulationError::InvalidRequest(
                "content path must not be empty".into(),
            ));
        }
        if self.save_root.as_os_str().is_empty() {
            return Err(EmulationError::InvalidRequest(
                "save root must not be empty".into(),
            ));
        }
        validate_component("system id", &self.system_id)?;
        validate_component("game id", &self.game_id)?;
        for key in self.core_options.keys() {
            if key.is_empty() || key.as_bytes().contains(&0) {
                return Err(EmulationError::InvalidRequest(
                    "core option key must not be empty or contain NUL".into(),
                ));
            }
        }
        for value in self.core_options.values() {
            if value.as_bytes().contains(&0) {
                return Err(EmulationError::InvalidRequest(
                    "core option value must not contain NUL".into(),
                ));
            }
        }
        Ok(())
    }

    pub(crate) fn save_directory(&self) -> PathBuf {
        self.save_root.join(&self.system_id).join(&self.game_id)
    }
}

fn validate_component(label: &str, value: &str) -> Result<(), EmulationError> {
    if value.is_empty() || value == "." || value == ".." {
        return Err(EmulationError::InvalidRequest(format!(
            "{label} must be a non-special path component"
        )));
    }
    if value.as_bytes().contains(&0) || value.contains('/') || value.contains('\\') {
        return Err(EmulationError::InvalidRequest(format!(
            "{label} must not contain a path separator or NUL"
        )));
    }
    if value.len() > 128 {
        return Err(EmulationError::InvalidRequest(format!(
            "{label} is too long"
        )));
    }
    Ok(())
}

/// Session metadata reported by the loaded core.
#[derive(Debug, Clone, PartialEq)]
pub struct SessionInfo {
    pub core_name: String,
    pub core_version: String,
    pub width: u32,
    pub height: u32,
    pub max_width: u32,
    pub max_height: u32,
    pub aspect_ratio: f32,
    pub fps: f64,
    pub sample_rate: f64,
    pub pixel_format: &'static str,
    pub has_battery_ram: bool,
}

/// Lifecycle state visible to a frontend.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeStatus {
    Stopped,
    Starting,
    Running,
    Paused,
    Stopping,
    Failed,
}

/// Bounded lifecycle notifications emitted by the worker.
#[derive(Debug, Clone, PartialEq)]
pub enum EmulationEvent {
    Starting,
    Started(SessionInfo),
    Paused,
    Resumed,
    Stopped { battery_bytes: usize },
    Failed { message: String },
}

/// A cheap status/transport summary for polling frontends.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeSnapshot {
    pub status: RuntimeStatus,
    pub frame_sequence: u64,
    pub overwritten_frames: u64,
    pub audio_buffered_frames: usize,
    pub audio_dropped_frames: u64,
    pub last_error: Option<String>,
}

/// A bounded runtime failure. Paths are deliberately not included in errors
/// emitted by the worker so UI logs do not accidentally disclose local layout.
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum EmulationError {
    #[error("invalid emulation request: {0}")]
    InvalidRequest(String),
    #[error("emulator core error: {0}")]
    Core(String),
    #[error("I/O error: {0}")]
    Io(String),
    #[error("emulator command queue is full")]
    CommandQueueFull,
    #[error("emulator worker is unavailable")]
    WorkerUnavailable,
    #[error("invalid player index: {0}")]
    InvalidPlayer(usize),
    #[error("emulator worker panicked")]
    WorkerPanicked,
}

impl From<std::io::Error> for EmulationError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error.to_string())
    }
}

struct Shared {
    status: Mutex<RuntimeStatus>,
    events: Mutex<VecDeque<EmulationEvent>>,
    video: Arc<Mutex<VideoSlot>>,
    audio: Arc<Mutex<AudioRing>>,
    inputs: Arc<AtomicInputs>,
    paused: std::sync::atomic::AtomicBool,
    last_error: Mutex<Option<String>>,
}

impl Shared {
    fn new() -> Self {
        Self {
            status: Mutex::new(RuntimeStatus::Stopped),
            events: Mutex::new(VecDeque::with_capacity(EVENT_CAPACITY)),
            video: Arc::new(Mutex::new(VideoSlot::new())),
            audio: Arc::new(Mutex::new(AudioRing::new())),
            inputs: Arc::new(AtomicInputs::new()),
            paused: std::sync::atomic::AtomicBool::new(false),
            last_error: Mutex::new(None),
        }
    }

    fn set_status(&self, status: RuntimeStatus) {
        if let Ok(mut current) = self.status.lock() {
            *current = status;
        }
    }

    fn status(&self) -> RuntimeStatus {
        self.status
            .lock()
            .map(|status| *status)
            .unwrap_or(RuntimeStatus::Failed)
    }

    fn push_event(&self, event: EmulationEvent) {
        if let Ok(mut events) = self.events.lock() {
            if events.len() >= EVENT_CAPACITY {
                events.pop_front();
            }
            events.push_back(event);
        }
    }

    fn clear_transport(&self) {
        if let Ok(mut video) = self.video.lock() {
            video.clear();
        }
        if let Ok(mut audio) = self.audio.lock() {
            audio.clear();
        }
        self.inputs.clear();
    }

    fn set_error(&self, error: &EmulationError) {
        if let Ok(mut last_error) = self.last_error.lock() {
            *last_error = Some(error.to_string());
        }
    }

    fn clear_error(&self) {
        if let Ok(mut last_error) = self.last_error.lock() {
            *last_error = None;
        }
    }

    fn force_pause(&self) {
        self.paused
            .store(true, std::sync::atomic::Ordering::Release);
    }

    fn clear_pause(&self) {
        self.paused
            .store(false, std::sync::atomic::Ordering::Release);
    }
}

enum WorkerCommand {
    Start(StartRequest),
    RunFrame,
    PauseChanged,
    Reset,
    Stop,
    Shutdown,
}

/// One worker-owned libretro session and its bounded frame/audio transport.
///
/// The selected core must return from its libretro callbacks; an in-process
/// core cannot be safely cancelled from another thread if it hangs.
pub struct EmulationRuntime {
    tx: SyncSender<WorkerCommand>,
    shared: Arc<Shared>,
    join: Option<JoinHandle<()>>,
}

impl EmulationRuntime {
    /// Start an idle worker. Core loading happens asynchronously on `start`.
    pub fn new() -> Result<Self, EmulationError> {
        let shared = Arc::new(Shared::new());
        let (tx, rx) = mpsc::sync_channel(COMMAND_CAPACITY);
        let worker_shared = Arc::clone(&shared);
        let join = thread::Builder::new()
            .name("retrolife-emulation".into())
            .spawn(move || worker_loop(rx, worker_shared))
            .map_err(EmulationError::from)?;
        Ok(Self {
            tx,
            shared,
            join: Some(join),
        })
    }

    /// Queue a new core/content session.
    pub fn start(&self, request: StartRequest) -> Result<(), EmulationError> {
        request.validate()?;
        self.try_send(WorkerCommand::Start(request))
    }

    /// Replace one player's complete libretro joypad mask.
    pub fn set_input(&self, player: usize, mask: u16) -> Result<(), EmulationError> {
        if !self.shared.inputs.set(player, mask) {
            return Err(EmulationError::InvalidPlayer(player));
        }
        Ok(())
    }

    /// Replace all four player masks atomically from the worker's perspective.
    pub fn set_input_masks(&self, masks: [u16; 4]) {
        for (player, mask) in masks.into_iter().enumerate() {
            let _ = self.shared.inputs.set(player, mask);
        }
    }

    /// Request a pause or resume. The worker applies the transition in order.
    pub fn set_paused(&self, paused: bool) -> Result<(), EmulationError> {
        let previous = self
            .shared
            .paused
            .swap(paused, std::sync::atomic::Ordering::AcqRel);
        match self.try_send(WorkerCommand::PauseChanged) {
            Ok(()) => Ok(()),
            Err(error) => {
                self.shared
                    .paused
                    .store(previous, std::sync::atomic::Ordering::Release);
                Err(error)
            }
        }
    }

    /// Queue one emulation frame. Calling it while paused is a harmless no-op.
    pub fn run_frame(&self) -> Result<(), EmulationError> {
        self.try_send(WorkerCommand::RunFrame)
    }

    /// Reset the currently loaded core.
    pub fn reset(&self) -> Result<(), EmulationError> {
        self.try_send(WorkerCommand::Reset)
    }

    /// Stop the current session and atomically persist battery RAM.
    pub fn stop(&self) -> Result<(), EmulationError> {
        self.try_send(WorkerCommand::Stop)
    }

    /// Drain lifecycle events in FIFO order.
    pub fn drain_events(&self) -> Vec<EmulationEvent> {
        self.shared
            .events
            .lock()
            .map(|mut events| events.drain(..).collect())
            .unwrap_or_default()
    }

    /// Clone the latest available RGBA frame without consuming it.
    pub fn latest_video_frame(&self) -> Option<transport::VideoFrame> {
        self.shared.video.lock().ok()?.latest()
    }

    /// Return a frame only when its sequence is newer than `after_sequence`.
    pub fn video_frame_after(&self, after_sequence: u64) -> Option<transport::VideoFrame> {
        self.shared.video.lock().ok()?.after(after_sequence)
    }

    /// Drain up to `max_frames` interleaved stereo PCM frames.
    pub fn drain_audio(&self, max_frames: usize) -> Vec<i16> {
        self.shared
            .audio
            .lock()
            .map(|mut audio| audio.drain_frames(max_frames))
            .unwrap_or_default()
    }

    /// Return current lifecycle and bounded transport metrics.
    pub fn snapshot(&self) -> RuntimeSnapshot {
        let (frame_sequence, overwritten_frames) = self
            .shared
            .video
            .lock()
            .map(|video| (video.sequence(), video.overwritten_frames()))
            .unwrap_or_default();
        let (audio_buffered_frames, audio_dropped_frames) = self
            .shared
            .audio
            .lock()
            .map(|audio| (audio.buffered_frames(), audio.dropped_frames()))
            .unwrap_or_default();
        RuntimeSnapshot {
            status: self.shared.status(),
            frame_sequence,
            overwritten_frames,
            audio_buffered_frames,
            audio_dropped_frames,
            last_error: self
                .shared
                .last_error
                .lock()
                .ok()
                .and_then(|error| error.clone()),
        }
    }

    /// Stop the worker and wait for it to release the dynamic core.
    pub fn shutdown(mut self) -> Result<(), EmulationError> {
        if self.join.is_none() {
            return Ok(());
        }
        // Shutdown must use the blocking send. A bounded queue may be full;
        // using try_send and then joining could wait forever because no
        // shutdown command would ever reach the worker.
        let send_result = send_shutdown(&self.tx);
        if let Some(join) = self.join.take() {
            let join_result = join.join().map_err(|_| EmulationError::WorkerPanicked);
            send_result?;
            join_result?;
        }
        if self.shared.status() == RuntimeStatus::Failed
            && let Some(message) = self
                .shared
                .last_error
                .lock()
                .ok()
                .and_then(|error| error.clone())
        {
            return Err(EmulationError::Core(message));
        }
        Ok(())
    }

    fn try_send(&self, command: WorkerCommand) -> Result<(), EmulationError> {
        self.tx.try_send(command).map_err(|error| match error {
            TrySendError::Full(_) => EmulationError::CommandQueueFull,
            TrySendError::Disconnected(_) => EmulationError::WorkerUnavailable,
        })
    }
}

impl Drop for EmulationRuntime {
    fn drop(&mut self) {
        if self.join.is_some() {
            let _ = send_shutdown(&self.tx);
            if let Some(join) = self.join.take() {
                let _ = join.join();
            }
        }
    }
}

fn worker_loop(rx: Receiver<WorkerCommand>, shared: Arc<Shared>) {
    let mut session: Option<CoreSession> = None;
    while let Ok(command) = rx.recv() {
        match command {
            WorkerCommand::Start(request) => {
                shared.set_status(RuntimeStatus::Starting);
                shared.push_event(EmulationEvent::Starting);
                shared.clear_error();
                if let Some(old_session) = session.as_mut() {
                    if let Err(error) = old_session.stop() {
                        shared.force_pause();
                        shared.set_status(RuntimeStatus::Failed);
                        shared.set_error(&error);
                        shared.push_event(EmulationEvent::Failed {
                            message: error.to_string(),
                        });
                        continue;
                    }
                    session = None;
                }
                shared.clear_transport();
                match CoreSession::start(
                    request,
                    Arc::clone(&shared.video),
                    Arc::clone(&shared.audio),
                    Arc::clone(&shared.inputs),
                ) {
                    Ok((new_session, info)) => {
                        shared.set_status(
                            if shared.paused.load(std::sync::atomic::Ordering::Acquire) {
                                RuntimeStatus::Paused
                            } else {
                                RuntimeStatus::Running
                            },
                        );
                        shared.push_event(EmulationEvent::Started(info));
                        session = Some(new_session);
                    }
                    Err(error) => {
                        shared.set_status(RuntimeStatus::Failed);
                        shared.set_error(&error);
                        shared.push_event(EmulationEvent::Failed {
                            message: error.to_string(),
                        });
                    }
                }
            }
            WorkerCommand::RunFrame => {
                if shared.paused.load(std::sync::atomic::Ordering::Acquire) {
                    continue;
                }
                let Some(current) = session.as_ref() else {
                    continue;
                };
                if let Err(error) = current.run_frame() {
                    session = fail_session(session.take(), &shared, error);
                }
            }
            WorkerCommand::PauseChanged => {
                let Some(_) = session.as_ref() else {
                    continue;
                };
                let paused = shared.paused.load(std::sync::atomic::Ordering::Acquire);
                match (paused, shared.status()) {
                    (true, RuntimeStatus::Running) => {
                        shared.set_status(RuntimeStatus::Paused);
                        shared.push_event(EmulationEvent::Paused);
                    }
                    (false, RuntimeStatus::Paused) => {
                        shared.set_status(RuntimeStatus::Running);
                        shared.push_event(EmulationEvent::Resumed);
                    }
                    _ => {}
                }
            }
            WorkerCommand::Reset => {
                if let Some(current) = session.as_ref() {
                    current.reset();
                }
            }
            WorkerCommand::Stop => {
                if let Some(current) = session.as_mut() {
                    shared.set_status(RuntimeStatus::Stopping);
                    match current.stop() {
                        Ok(battery_bytes) => {
                            session = None;
                            shared.clear_pause();
                            shared.clear_error();
                            shared.set_status(RuntimeStatus::Stopped);
                            shared.push_event(EmulationEvent::Stopped { battery_bytes });
                        }
                        Err(error) => {
                            shared.force_pause();
                            shared.set_status(RuntimeStatus::Failed);
                            shared.set_error(&error);
                            shared.push_event(EmulationEvent::Failed {
                                message: error.to_string(),
                            });
                        }
                    }
                } else if shared.status() != RuntimeStatus::Failed {
                    shared.set_status(RuntimeStatus::Stopped);
                }
            }
            WorkerCommand::Shutdown => {
                if let Some(current) = session.as_mut() {
                    match current.stop() {
                        Ok(_) => {
                            shared.clear_pause();
                            shared.clear_error();
                            shared.set_status(RuntimeStatus::Stopped);
                        }
                        Err(error) => {
                            shared.force_pause();
                            shared.set_status(RuntimeStatus::Failed);
                            shared.set_error(&error);
                            shared.push_event(EmulationEvent::Failed {
                                message: error.to_string(),
                            });
                        }
                    }
                } else if shared.status() != RuntimeStatus::Failed {
                    shared.set_status(RuntimeStatus::Stopped);
                }
                break;
            }
        }
    }
}

fn fail_session(
    session: Option<CoreSession>,
    shared: &Shared,
    error: EmulationError,
) -> Option<CoreSession> {
    drop(session);
    shared.force_pause();
    shared.set_status(RuntimeStatus::Failed);
    shared.set_error(&error);
    shared.push_event(EmulationEvent::Failed {
        message: error.to_string(),
    });
    None
}

/// Libretro joypad bit for A.
pub use transport::JOYPAD_A;
/// Libretro joypad bit for the B button.
pub use transport::JOYPAD_B;
/// Libretro joypad bit for Down.
pub use transport::JOYPAD_DOWN;
/// Libretro joypad bit for L.
pub use transport::JOYPAD_L;
/// Libretro joypad bit for Left.
pub use transport::JOYPAD_LEFT;
/// Libretro joypad bit for R.
pub use transport::JOYPAD_R;
/// Libretro joypad bit for Right.
pub use transport::JOYPAD_RIGHT;
/// Libretro joypad bit for Select.
pub use transport::JOYPAD_SELECT;
/// Libretro joypad bit for Start.
pub use transport::JOYPAD_START;
/// Libretro joypad bit for Up.
pub use transport::JOYPAD_UP;
/// Libretro joypad bit for X.
pub use transport::JOYPAD_X;
/// Libretro joypad bit for the Y button.
pub use transport::JOYPAD_Y;

pub use transport::{VideoFrame, VideoFrameInfo};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn save_directory_is_scoped_by_stable_ids() {
        let request = StartRequest::new("core", "game.sfc", "/tmp/saves", "snes", "mario");
        assert_eq!(
            request.save_directory(),
            std::path::Path::new("/tmp/saves")
                .join("snes")
                .join("mario")
        );
    }

    #[test]
    fn path_components_reject_traversal_and_separators() {
        let mut request = StartRequest::new("core", "game.sfc", "saves", "snes", "game");
        request.game_id = "../other".into();
        assert!(matches!(
            request.validate(),
            Err(EmulationError::InvalidRequest(_))
        ));
        request.game_id = "safe".into();
        request.system_id = "with\\separator".into();
        assert!(request.validate().is_err());
    }

    #[test]
    fn event_queue_and_status_are_bounded() {
        let shared = Shared::new();
        for _ in 0..(EVENT_CAPACITY + 3) {
            shared.push_event(EmulationEvent::Starting);
        }
        assert_eq!(
            shared.events.lock().expect("event lock").len(),
            EVENT_CAPACITY
        );
    }

    #[test]
    fn runtime_can_start_and_shutdown_without_a_core() {
        let runtime = EmulationRuntime::new().expect("worker");
        runtime.shutdown().expect("shutdown");
    }

    #[test]
    fn shutdown_send_waits_for_space_in_a_full_command_queue() {
        let (tx, rx) = mpsc::sync_channel(1);
        tx.try_send(WorkerCommand::RunFrame)
            .expect("fill command queue");

        let sender = thread::spawn(move || send_shutdown(&tx));
        let receiver = thread::spawn(move || {
            assert!(matches!(rx.recv(), Ok(WorkerCommand::RunFrame)));
            assert!(matches!(rx.recv(), Ok(WorkerCommand::Shutdown)));
        });

        receiver.join().expect("receiver");
        sender.join().expect("sender").expect("shutdown delivery");
    }
}
