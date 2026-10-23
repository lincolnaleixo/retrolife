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

mod checkpoints;
mod core_identity;
mod libretro;
mod persistence;
mod transport;

pub use checkpoints::{
    QUICK_SLOT, RECOVERY_SLOT, STATE_SLOTS, SaveStateOperation, SaveStateSlot, SaveStatesSnapshot,
};
use libretro::CoreSession;
use std::collections::{BTreeMap, VecDeque};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
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

/// Identity of the bytes actually loaded by the worker, independent of a
/// frontend's title, filename or catalogue identifier.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentIdentity {
    pub system_id: String,
    /// SHA-256 in lowercase hex. For SNES, a 512-byte copier header is excluded
    /// when the file length is 512 bytes more than a multiple of 32 KiB.
    pub sha256: String,
}

/// Read-only observation performed on the emulation worker after every frame.
///
/// Callbacks must be bounded and must not wait for frontend work. The borrowed
/// RAM is valid only during `frame_completed`; no core pointer crosses this
/// boundary. Missing or nonstandard memory is represented by `None`, rather
/// than guessed or truncated. No observations are made for paused frames.
pub trait FrameObserver: Send {
    fn session_started(&mut self, content: &ContentIdentity, info: &SessionInfo);
    /// SNES system RAM (exactly 128 KiB, starting at CPU address $7E0000).
    fn frame_completed(&mut self, system_ram: Option<&[u8]>);
    /// A reset invalidates transition baselines, but need not discard awards.
    fn reset(&mut self);
    /// Retain any cumulative observations needed by the frontend to flush them.
    fn session_stopped(&mut self);
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
    #[error("checkpoint: {0}")]
    Checkpoint(String),
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
    save_states: Mutex<SaveStatesSnapshot>,
    next_state_operation: AtomicU64,
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
            save_states: Mutex::new(SaveStatesSnapshot::default()),
            next_state_operation: AtomicU64::new(1),
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
    SaveState { id: u64, slot: u8 },
    LoadState { id: u64, slot: u8 },
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
        Self::create(None)
    }

    /// Start an idle worker with a synchronous read-only frame observer.
    pub fn with_observer(observer: Box<dyn FrameObserver>) -> Result<Self, EmulationError> {
        Self::create(Some(observer))
    }

    fn create(observer: Option<Box<dyn FrameObserver>>) -> Result<Self, EmulationError> {
        let shared = Arc::new(Shared::new());
        let (tx, rx) = mpsc::sync_channel(COMMAND_CAPACITY);
        let worker_shared = Arc::clone(&shared);
        let join = thread::Builder::new()
            .name("retrolife-emulation".into())
            .spawn(move || worker_loop(rx, worker_shared, observer))
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
        let mut states = self
            .shared
            .save_states
            .lock()
            .map_err(|_| EmulationError::WorkerUnavailable)?;
        if states.busy {
            return Err(EmulationError::Checkpoint(
                "Wait for the checkpoint operation to finish.".into(),
            ));
        }
        self.try_send(WorkerCommand::Start(request))?;
        *states = SaveStatesSnapshot::default();
        Ok(())
    }

    /// Replace one player's complete libretro joypad mask.
    pub fn set_input(&self, player: usize, mask: u16) -> Result<(), EmulationError> {
        let mask = if self.state_operation_busy() { 0 } else { mask };
        if !self.shared.inputs.set(player, mask) {
            return Err(EmulationError::InvalidPlayer(player));
        }
        Ok(())
    }

    /// Replace all four player masks atomically from the worker's perspective.
    pub fn set_input_masks(&self, masks: [u16; 4]) {
        if self.state_operation_busy() {
            self.shared.inputs.clear();
            return;
        }
        for (player, mask) in masks.into_iter().enumerate() {
            let _ = self.shared.inputs.set(player, mask);
        }
    }

    /// Request a pause or resume. The worker applies the transition in order.
    pub fn set_paused(&self, paused: bool) -> Result<(), EmulationError> {
        if !paused
            && self
                .shared
                .save_states
                .lock()
                .is_ok_and(|states| states.busy || !states.can_resume)
        {
            return Err(EmulationError::Checkpoint(
                "The checkpoint operation is pending or this session cannot resume safely.".into(),
            ));
        }
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
        if self.state_operation_busy() {
            return Ok(());
        }
        self.try_send(WorkerCommand::RunFrame)
    }

    fn state_operation_busy(&self) -> bool {
        self.shared
            .save_states
            .lock()
            .map(|states| states.busy)
            .unwrap_or(true)
    }

    /// Queue a checkpoint write. Slots 0–5 are manual; 6 is Quick Save.
    pub fn save_state(&self, slot: u8) -> Result<u64, EmulationError> {
        if slot > QUICK_SLOT {
            return Err(EmulationError::Checkpoint(
                "The recovery slot is read-only.".into(),
            ));
        }
        self.queue_state_operation(slot, false)
    }

    /// Queue a restore after atomically capturing the current state in slot 7.
    pub fn load_state(&self, slot: u8) -> Result<u64, EmulationError> {
        if slot > RECOVERY_SLOT {
            return Err(EmulationError::Checkpoint(
                "Invalid checkpoint slot.".into(),
            ));
        }
        self.queue_state_operation(slot, true)
    }

    fn queue_state_operation(&self, slot: u8, load: bool) -> Result<u64, EmulationError> {
        let mut states = self
            .shared
            .save_states
            .lock()
            .map_err(|_| EmulationError::WorkerUnavailable)?;
        if states.busy {
            return Err(EmulationError::Checkpoint(
                "A checkpoint operation is already running.".into(),
            ));
        }
        if !states.supported
            || !matches!(
                self.shared.status(),
                RuntimeStatus::Running | RuntimeStatus::Paused
            )
        {
            return Err(EmulationError::Checkpoint(
                "No checkpoint-capable game is active.".into(),
            ));
        }
        if !states.can_resume {
            return Err(EmulationError::Checkpoint("Stop this session after the failed rollback. The recovery checkpoint remains on disk.".into()));
        }
        let id = self
            .shared
            .next_state_operation
            .fetch_add(1, Ordering::Relaxed);
        self.try_send(if load {
            WorkerCommand::LoadState { id, slot }
        } else {
            WorkerCommand::SaveState { id, slot }
        })?;
        states.busy = true;
        states.operation = SaveStateOperation {
            id,
            kind: if load { "load" } else { "save" }.into(),
            slot,
            status: "pending".into(),
            error: String::new(),
        };
        self.shared.inputs.clear();
        Ok(id)
    }

    /// Cached worker result; no core calls or filesystem access on the caller.
    pub fn save_states_snapshot(&self) -> SaveStatesSnapshot {
        self.shared
            .save_states
            .lock()
            .map(|states| SaveStatesSnapshot {
                supported: states.supported,
                busy: states.busy,
                slots: states.slots.clone(),
                operation: states.operation.clone(),
                discontinuity: states.discontinuity,
                can_resume: states.can_resume,
                previews: Vec::new(),
            })
            .unwrap_or_default()
    }

    /// Cached raw RGBA preview, bounded to 512×512, without frontend shaders.
    pub fn save_state_preview(&self, slot: u8) -> Vec<u8> {
        self.shared
            .save_states
            .lock()
            .ok()
            .and_then(|states| states.previews.get(usize::from(slot)).cloned())
            .unwrap_or_default()
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

fn refresh_state_cache(current: &CoreSession, shared: &Shared) {
    let mut refreshed = SaveStatesSnapshot::default();
    current.state_store.refresh(&mut refreshed);
    let supported = current.checkpoint_size().is_ok();
    if let Ok(mut states) = shared.save_states.lock() {
        states.supported = supported;
        states.slots = refreshed.slots;
        states.previews = refreshed.previews;
        states.can_resume = current.state_restore_safe;
    }
}

fn restore_checkpoint(
    current: &mut CoreSession,
    shared: &Shared,
    observer: &mut Option<Box<dyn FrameObserver>>,
    slot: u8,
) -> (Result<(), EmulationError>, bool) {
    let mut attempted = false;
    let result = (|| {
        // Read the requested snapshot before replacing Recovery, including when
        // loading slot 7 itself. A corrupt/incompatible request never mutates core.
        let target = current.state_store.load(slot)?;
        let recovery_bytes = current.serialize_state()?;
        let frame = shared.video.lock().ok().and_then(|video| video.latest());
        let recovery = current
            .state_store
            .save(RECOVERY_SLOT, recovery_bytes, frame.as_ref())?;
        attempted = true;
        if let Some(observer) = observer.as_mut() {
            observer.reset();
        }
        let restored = current.unserialize_state(&target.state);
        let visible = if restored {
            Some(&target)
        } else if current.unserialize_state(&recovery.state) {
            Some(&recovery)
        } else {
            current.state_restore_safe = false;
            shared.force_pause();
            shared.set_status(RuntimeStatus::Paused);
            shared.push_event(EmulationEvent::Paused);
            None
        };
        shared.inputs.clear();
        if let Ok(mut audio) = shared.audio.lock() {
            audio.clear();
        }
        if let Ok(mut video) = shared.video.lock() {
            if let Some(visible) = visible {
                let (width, height) = visible.preview_size();
                video.restore_preview(visible.preview.clone(), width, height);
            } else {
                video.restore_preview(Vec::new(), 0, 0);
            }
        }
        if restored {
            Ok(())
        } else if current.state_restore_safe {
            Err(EmulationError::Checkpoint("The core rejected this checkpoint. Your previous state was restored from Recovery.".into()))
        } else {
            Err(EmulationError::Checkpoint("The core rejected both the checkpoint and rollback. The session is paused; stop it before continuing. The existing battery save is unchanged and Recovery remains on disk.".into()))
        }
    })();
    (result, attempted)
}

fn worker_loop(
    rx: Receiver<WorkerCommand>,
    shared: Arc<Shared>,
    mut observer: Option<Box<dyn FrameObserver>>,
) {
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
                    if let Some(observer) = observer.as_mut() {
                        observer.session_stopped();
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
                        refresh_state_cache(&new_session, &shared);
                        if let Some(observer) = observer.as_mut() {
                            observer.session_started(new_session.content_identity(), &info);
                        }
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
                if shared.paused.load(std::sync::atomic::Ordering::Acquire)
                    || shared.save_states.lock().is_ok_and(|states| states.busy)
                {
                    continue;
                }
                let Some(current) = session.as_ref() else {
                    continue;
                };
                if let Err(error) = current.run_frame() {
                    session = fail_session(session.take(), &shared, error);
                    if let Some(observer) = observer.as_mut() {
                        observer.session_stopped();
                    }
                } else if let Some(observer) = observer.as_mut() {
                    current.observe_frame(observer.as_mut());
                }
                if let Some(current) = session.as_ref()
                    && shared
                        .save_states
                        .lock()
                        .is_ok_and(|states| !states.supported)
                    && current.checkpoint_size().is_ok()
                {
                    refresh_state_cache(current, &shared);
                }
            }
            WorkerCommand::PauseChanged => {
                let Some(current) = session.as_ref() else {
                    continue;
                };
                if !current.state_restore_safe {
                    shared
                        .paused
                        .store(true, std::sync::atomic::Ordering::Release);
                    shared.set_status(RuntimeStatus::Paused);
                    continue;
                }
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
                    if !current.state_restore_safe {
                        continue;
                    }
                    current.reset();
                    if let Some(observer) = observer.as_mut() {
                        observer.reset();
                    }
                }
            }
            WorkerCommand::SaveState { id, slot } | WorkerCommand::LoadState { id, slot } => {
                let load = matches!(command, WorkerCommand::LoadState { .. });
                let mut discontinuity = false;
                let result = if let Some(current) = session.as_mut() {
                    if load {
                        let (result, attempted) =
                            restore_checkpoint(current, &shared, &mut observer, slot);
                        discontinuity = attempted;
                        result
                    } else {
                        current.serialize_state().and_then(|bytes| {
                            let frame = shared.video.lock().ok().and_then(|video| video.latest());
                            current
                                .state_store
                                .save(slot, bytes, frame.as_ref())
                                .map(|_| ())
                        })
                    }
                } else {
                    Err(EmulationError::Checkpoint(
                        "The game session ended before this operation.".into(),
                    ))
                };
                if let Some(current) = session.as_ref() {
                    refresh_state_cache(current, &shared);
                }
                if let Ok(mut states) = shared.save_states.lock()
                    && states.operation.id == id
                {
                    states.busy = false;
                    states.operation.status =
                        if result.is_ok() { "complete" } else { "failed" }.into();
                    states.operation.error = result
                        .err()
                        .map(|error| error.to_string())
                        .unwrap_or_default();
                    if discontinuity {
                        states.discontinuity = states.discontinuity.saturating_add(1);
                    }
                    states.can_resume = session
                        .as_ref()
                        .is_none_or(|current| current.state_restore_safe);
                }
            }
            WorkerCommand::Stop => {
                if let Some(current) = session.as_mut() {
                    shared.set_status(RuntimeStatus::Stopping);
                    match current.stop() {
                        Ok(battery_bytes) => {
                            if let Some(observer) = observer.as_mut() {
                                observer.session_stopped();
                            }
                            session = None;
                            if let Ok(mut states) = shared.save_states.lock() {
                                *states = SaveStatesSnapshot::default();
                            }
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
                            if let Some(observer) = observer.as_mut() {
                                observer.session_stopped();
                            }
                            shared.clear_pause();
                            shared.clear_error();
                            shared.set_status(RuntimeStatus::Stopped);
                        }
                        Err(error) => {
                            if let Some(observer) = observer.as_mut() {
                                observer.session_stopped();
                            }
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
