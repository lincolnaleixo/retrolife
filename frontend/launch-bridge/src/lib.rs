use godot::classes::Node;
use godot::prelude::*;
use retrolife_core::{GameLaunchPlan, LaunchConfiguration};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, VecDeque},
    fs::{self, File},
    io::Read,
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Stdio},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc::{Receiver, SyncSender, TryRecvError, TrySendError, sync_channel},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const DTO_SCHEMA_VERSION: u32 = 1;
const QUEUE_CAPACITY: usize = 2;
const TERMINAL_RETENTION: usize = 32;
const POLL_INTERVAL: Duration = Duration::from_millis(20);

struct RetroLifeLaunchExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RetroLifeLaunchExtension {}

#[derive(GodotClass)]
#[class(base=Node)]
struct RetroLifeLauncher {
    runtime: LaunchRuntime,
    base: Base<Node>,
}

#[godot_api]
impl INode for RetroLifeLauncher {
    fn init(base: Base<Node>) -> Self {
        Self {
            runtime: LaunchRuntime::new(),
            base,
        }
    }
}

#[godot_api]
impl RetroLifeLauncher {
    #[signal]
    fn launch_updated(snapshot_json: GString);

    #[signal]
    fn launch_terminal(snapshot_json: GString);

    #[func]
    fn load_launch_configuration_json(&mut self, configuration_json: GString) -> GString {
        let result = self
            .runtime
            .load_configuration(&configuration_json.to_string());
        response_string(result)
    }

    #[func]
    fn launch_configuration_status_json(&self) -> GString {
        response_string(self.runtime.configuration_status())
    }

    #[func]
    fn launch_availability_json(&self, game_id: GString) -> GString {
        response_string(self.runtime.availability(&game_id.to_string()))
    }

    #[func]
    fn queue_game_launch_json(&mut self, game_id: GString) -> GString {
        response_string(self.runtime.queue(&game_id.to_string()))
    }

    #[func]
    fn launch_status_json(&self, operation_id: GString) -> GString {
        response_string(self.runtime.status(&operation_id.to_string()))
    }

    #[func]
    fn cancel_game_launch_json(&mut self, operation_id: GString) -> GString {
        response_string(self.runtime.cancel(&operation_id.to_string()))
    }

    #[func]
    fn list_launches_json(&self) -> GString {
        response_string(self.runtime.list())
    }

    #[func]
    fn drain_launch_events_json(&mut self) -> GString {
        let events = self.runtime.drain_events();
        for snapshot in &events {
            let json =
                serde_json::to_string(snapshot).expect("launch snapshots must always serialize");
            self.base_mut()
                .emit_signal("launch_updated", vslice![GString::from(json.as_str())]);
            if snapshot.state.is_terminal() {
                self.base_mut()
                    .emit_signal("launch_terminal", vslice![GString::from(json.as_str())]);
            }
        }
        response_string::<Vec<LaunchSnapshot>>(Ok(events))
    }

    #[func]
    fn shutdown_launch_runtime_json(&mut self) -> GString {
        self.runtime.shutdown();
        response_string::<RuntimeStatus>(Ok(RuntimeStatus {
            accepting: false,
            queue_capacity: QUEUE_CAPACITY,
            terminal_retention: TERMINAL_RETENTION,
        }))
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum LaunchState {
    Queued,
    Preparing,
    Starting,
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl LaunchState {
    fn is_terminal(self) -> bool {
        matches!(self, Self::Completed | Self::Failed | Self::Cancelled)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LaunchProgress {
    completed_units: u64,
    total_units: u64,
    percent: u8,
    message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LaunchFailure {
    code: String,
    message: String,
    retryable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LaunchResult {
    game_id: String,
    launcher_id: String,
    executable: String,
    arguments: Vec<String>,
    session_directory: String,
    save_directory: String,
    input_profile_path: String,
    observed_launch_path: Option<String>,
    exit_code: Option<i32>,
    duration_ms: u64,
    stdout: String,
    stderr: String,
    stdout_truncated: bool,
    stderr_truncated: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LaunchSnapshot {
    schema_version: u32,
    operation_id: String,
    kind: &'static str,
    state: LaunchState,
    game_id: String,
    progress: LaunchProgress,
    cancellable: bool,
    created_at_ms: u64,
    updated_at_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<LaunchResult>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<LaunchFailure>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ConfigurationStatus {
    configured: bool,
    launcher_count: usize,
    game_count: usize,
    input_profile_count: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct LaunchAvailability {
    game_id: String,
    available: bool,
    system_id: Option<String>,
    launcher_id: Option<String>,
    reason: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct QueueReceipt {
    operation_id: String,
    game_id: String,
    state: LaunchState,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CancelReceipt {
    operation_id: String,
    cancellation_requested: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeStatus {
    accepting: bool,
    queue_capacity: usize,
    terminal_retention: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BridgeResponse<T: Serialize> {
    schema_version: u32,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<LaunchFailure>,
}

struct LaunchRequest {
    operation_id: String,
    game_id: String,
    configuration: LaunchConfiguration,
    cancellation: Arc<AtomicBool>,
}

struct LaunchRuntime {
    configuration: Arc<Mutex<Option<LaunchConfiguration>>>,
    snapshots: Arc<Mutex<HashMap<String, LaunchSnapshot>>>,
    cancellations: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    terminal_order: Arc<Mutex<VecDeque<String>>>,
    request_sender: SyncSender<LaunchRequest>,
    event_sender: SyncSender<LaunchSnapshot>,
    event_receiver: Receiver<LaunchSnapshot>,
    shutdown: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
    next_operation: AtomicU64,
}

impl LaunchRuntime {
    fn new() -> Self {
        let configuration = Arc::new(Mutex::new(None));
        let snapshots = Arc::new(Mutex::new(HashMap::new()));
        let cancellations = Arc::new(Mutex::new(HashMap::new()));
        let terminal_order = Arc::new(Mutex::new(VecDeque::new()));
        let shutdown = Arc::new(AtomicBool::new(false));
        let (request_sender, request_receiver) = sync_channel::<LaunchRequest>(QUEUE_CAPACITY);
        let (event_sender, event_receiver) = sync_channel::<LaunchSnapshot>(256);

        let worker_snapshots = Arc::clone(&snapshots);
        let worker_cancellations = Arc::clone(&cancellations);
        let worker_terminal_order = Arc::clone(&terminal_order);
        let worker_shutdown = Arc::clone(&shutdown);
        let worker_events = event_sender.clone();
        let worker = thread::Builder::new()
            .name("retrolife-launch-worker".to_owned())
            .spawn(move || {
                worker_loop(
                    request_receiver,
                    worker_snapshots,
                    worker_cancellations,
                    worker_terminal_order,
                    worker_events,
                    worker_shutdown,
                );
            })
            .expect("the RetroLife launch worker must start");

        Self {
            configuration,
            snapshots,
            cancellations,
            terminal_order,
            request_sender,
            event_sender,
            event_receiver,
            shutdown,
            worker: Some(worker),
            next_operation: AtomicU64::new(1),
        }
    }

    fn load_configuration(&mut self, json: &str) -> Result<ConfigurationStatus, LaunchFailure> {
        if self.shutdown.load(Ordering::SeqCst) {
            return Err(failure(
                "runtimeStopped",
                "The launch runtime is not accepting configuration changes",
                false,
            ));
        }
        let configuration = retrolife_core::decode_launch_configuration(json)
            .map_err(|error| failure("configurationInvalid", error, false))?;
        let status = ConfigurationStatus {
            configured: true,
            launcher_count: configuration.launchers.len(),
            game_count: configuration.games.len(),
            input_profile_count: configuration.input_profiles.len(),
        };
        *self.configuration.lock().map_err(|_| lock_failure())? = Some(configuration);
        Ok(status)
    }

    fn configuration_status(&self) -> Result<ConfigurationStatus, LaunchFailure> {
        let configuration = self.configuration.lock().map_err(|_| lock_failure())?;
        Ok(match configuration.as_ref() {
            Some(configuration) => ConfigurationStatus {
                configured: true,
                launcher_count: configuration.launchers.len(),
                game_count: configuration.games.len(),
                input_profile_count: configuration.input_profiles.len(),
            },
            None => ConfigurationStatus {
                configured: false,
                launcher_count: 0,
                game_count: 0,
                input_profile_count: 0,
            },
        })
    }

    fn availability(&self, game_id: &str) -> Result<LaunchAvailability, LaunchFailure> {
        let game_id = game_id.trim();
        if game_id.is_empty() {
            return Err(failure("gameIdRequired", "gameId cannot be empty", false));
        }
        let configuration = self.configuration.lock().map_err(|_| lock_failure())?;
        let Some(configuration) = configuration.as_ref() else {
            return Ok(LaunchAvailability {
                game_id: game_id.to_owned(),
                available: false,
                system_id: None,
                launcher_id: None,
                reason: "Launch configuration is not loaded".to_owned(),
            });
        };
        let Some(binding) = configuration.binding(game_id) else {
            return Ok(LaunchAvailability {
                game_id: game_id.to_owned(),
                available: false,
                system_id: None,
                launcher_id: None,
                reason: "No launch binding exists for this game".to_owned(),
            });
        };
        let launcher = configuration.launcher_for(binding);
        Ok(LaunchAvailability {
            game_id: game_id.to_owned(),
            available: launcher.is_some(),
            system_id: Some(binding.system_id.clone()),
            launcher_id: launcher.map(|profile| profile.id.clone()),
            reason: if launcher.is_some() {
                "Ready to prepare and launch".to_owned()
            } else {
                "No launcher supports this system".to_owned()
            },
        })
    }

    fn queue(&mut self, game_id: &str) -> Result<QueueReceipt, LaunchFailure> {
        if self.shutdown.load(Ordering::SeqCst) {
            return Err(failure(
                "runtimeStopped",
                "The launch runtime is not accepting new work",
                false,
            ));
        }
        let game_id = game_id.trim();
        if game_id.is_empty() {
            return Err(failure("gameIdRequired", "gameId cannot be empty", false));
        }
        {
            let snapshots = self.snapshots.lock().map_err(|_| lock_failure())?;
            if snapshots
                .values()
                .any(|snapshot| snapshot.game_id == game_id && !snapshot.state.is_terminal())
            {
                return Err(failure(
                    "launchAlreadyActive",
                    "This game already has an active launch operation",
                    true,
                ));
            }
        }
        let configuration = self
            .configuration
            .lock()
            .map_err(|_| lock_failure())?
            .clone()
            .ok_or_else(|| {
                failure(
                    "configurationMissing",
                    "Launch configuration is not loaded",
                    false,
                )
            })?;
        if configuration.binding(game_id).is_none() {
            return Err(failure(
                "launchUnavailable",
                format!("game {game_id} has no launch binding"),
                false,
            ));
        }

        let operation_id = format!(
            "launch-{:016x}",
            self.next_operation.fetch_add(1, Ordering::SeqCst)
        );
        let cancellation = Arc::new(AtomicBool::new(false));
        let snapshot = LaunchSnapshot::new(
            &operation_id,
            game_id,
            LaunchState::Queued,
            0,
            "Queued for preparation",
            true,
        );
        self.snapshots
            .lock()
            .map_err(|_| lock_failure())?
            .insert(operation_id.clone(), snapshot.clone());
        self.cancellations
            .lock()
            .map_err(|_| lock_failure())?
            .insert(operation_id.clone(), Arc::clone(&cancellation));

        let request = LaunchRequest {
            operation_id: operation_id.clone(),
            game_id: game_id.to_owned(),
            configuration,
            cancellation,
        };
        match self.request_sender.try_send(request) {
            Ok(()) => {
                let _ = self.event_sender.try_send(snapshot);
                Ok(QueueReceipt {
                    operation_id,
                    game_id: game_id.to_owned(),
                    state: LaunchState::Queued,
                })
            }
            Err(TrySendError::Full(_)) => {
                self.remove_operation(&operation_id);
                Err(failure(
                    "launchQueueFull",
                    format!("The launch queue is full at capacity {QUEUE_CAPACITY}"),
                    true,
                ))
            }
            Err(TrySendError::Disconnected(_)) => {
                self.remove_operation(&operation_id);
                Err(failure(
                    "launchWorkerUnavailable",
                    "The launch worker is unavailable",
                    true,
                ))
            }
        }
    }

    fn status(&self, operation_id: &str) -> Result<LaunchSnapshot, LaunchFailure> {
        self.snapshots
            .lock()
            .map_err(|_| lock_failure())?
            .get(operation_id.trim())
            .cloned()
            .ok_or_else(|| {
                failure(
                    "launchUnknown",
                    format!("Unknown launch operation {}", operation_id.trim()),
                    false,
                )
            })
    }

    fn list(&self) -> Result<Vec<LaunchSnapshot>, LaunchFailure> {
        let mut snapshots = self
            .snapshots
            .lock()
            .map_err(|_| lock_failure())?
            .values()
            .cloned()
            .collect::<Vec<_>>();
        snapshots.sort_by(|left, right| left.operation_id.cmp(&right.operation_id));
        Ok(snapshots)
    }

    fn cancel(&mut self, operation_id: &str) -> Result<CancelReceipt, LaunchFailure> {
        let operation_id = operation_id.trim();
        let snapshot = self.status(operation_id)?;
        if snapshot.state.is_terminal() {
            return Ok(CancelReceipt {
                operation_id: operation_id.to_owned(),
                cancellation_requested: false,
            });
        }
        let cancellations = self.cancellations.lock().map_err(|_| lock_failure())?;
        let cancellation = cancellations.get(operation_id).ok_or_else(|| {
            failure(
                "launchUnknown",
                format!("Unknown launch operation {operation_id}"),
                false,
            )
        })?;
        cancellation.store(true, Ordering::SeqCst);
        Ok(CancelReceipt {
            operation_id: operation_id.to_owned(),
            cancellation_requested: true,
        })
    }

    fn drain_events(&mut self) -> Vec<LaunchSnapshot> {
        let mut events = Vec::new();
        loop {
            match self.event_receiver.try_recv() {
                Ok(event) => events.push(event),
                Err(TryRecvError::Empty | TryRecvError::Disconnected) => break,
            }
        }
        events
    }

    fn shutdown(&mut self) {
        if self.shutdown.swap(true, Ordering::SeqCst) {
            return;
        }
        if let Ok(cancellations) = self.cancellations.lock() {
            for cancellation in cancellations.values() {
                cancellation.store(true, Ordering::SeqCst);
            }
        }
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }

    fn remove_operation(&self, operation_id: &str) {
        if let Ok(mut snapshots) = self.snapshots.lock() {
            snapshots.remove(operation_id);
        }
        if let Ok(mut cancellations) = self.cancellations.lock() {
            cancellations.remove(operation_id);
        }
    }
}

impl Drop for LaunchRuntime {
    fn drop(&mut self) {
        self.shutdown();
    }
}

impl LaunchSnapshot {
    fn new(
        operation_id: &str,
        game_id: &str,
        state: LaunchState,
        percent: u8,
        message: impl Into<String>,
        cancellable: bool,
    ) -> Self {
        let now = now_ms();
        Self {
            schema_version: DTO_SCHEMA_VERSION,
            operation_id: operation_id.to_owned(),
            kind: "prepareAndLaunchGame",
            state,
            game_id: game_id.to_owned(),
            progress: LaunchProgress {
                completed_units: u64::from(percent),
                total_units: 100,
                percent,
                message: message.into(),
            },
            cancellable,
            created_at_ms: now,
            updated_at_ms: now,
            result: None,
            error: None,
        }
    }
}

fn worker_loop(
    request_receiver: Receiver<LaunchRequest>,
    snapshots: Arc<Mutex<HashMap<String, LaunchSnapshot>>>,
    cancellations: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    terminal_order: Arc<Mutex<VecDeque<String>>>,
    event_sender: SyncSender<LaunchSnapshot>,
    shutdown: Arc<AtomicBool>,
) {
    while !shutdown.load(Ordering::SeqCst) {
        match request_receiver.recv_timeout(Duration::from_millis(50)) {
            Ok(request) => run_launch(
                request,
                &snapshots,
                &cancellations,
                &terminal_order,
                &event_sender,
                &shutdown,
            ),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
}

fn run_launch(
    request: LaunchRequest,
    snapshots: &Arc<Mutex<HashMap<String, LaunchSnapshot>>>,
    cancellations: &Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    terminal_order: &Arc<Mutex<VecDeque<String>>>,
    event_sender: &SyncSender<LaunchSnapshot>,
    shutdown: &Arc<AtomicBool>,
) {
    publish(
        snapshot_from_existing(
            snapshots,
            &request.operation_id,
            LaunchState::Preparing,
            10,
            "Resolving the Rust launch plan",
            true,
            None,
            None,
        ),
        snapshots,
        cancellations,
        terminal_order,
        event_sender,
    );

    if cancelled(&request, shutdown) {
        publish_cancelled(
            &request,
            snapshots,
            cancellations,
            terminal_order,
            event_sender,
            "Launch cancelled before preparation",
        );
        return;
    }

    let plan = match retrolife_core::build_game_launch_plan(
        &request.configuration,
        &request.game_id,
        &request.operation_id,
    ) {
        Ok(plan) => plan,
        Err(error) => {
            publish_failed(
                &request,
                snapshots,
                cancellations,
                terminal_order,
                event_sender,
                "launchPlanInvalid",
                error,
                false,
                None,
            );
            return;
        }
    };

    if let Err(error) = prepare_filesystem(&plan) {
        publish_failed(
            &request,
            snapshots,
            cancellations,
            terminal_order,
            event_sender,
            "launchPreparationFailed",
            error,
            true,
            None,
        );
        return;
    }

    if cancelled(&request, shutdown) {
        publish_cancelled(
            &request,
            snapshots,
            cancellations,
            terminal_order,
            event_sender,
            "Launch cancelled after preparation",
        );
        return;
    }

    publish(
        snapshot_from_existing(
            snapshots,
            &request.operation_id,
            LaunchState::Starting,
            35,
            "Starting the configured launcher",
            true,
            None,
            None,
        ),
        snapshots,
        cancellations,
        terminal_order,
        event_sender,
    );

    let started_at = Instant::now();
    let stdout_path = PathBuf::from(&plan.session_directory).join("stdout.log");
    let stderr_path = PathBuf::from(&plan.session_directory).join("stderr.log");
    let stdout_file = match File::create(&stdout_path) {
        Ok(file) => file,
        Err(error) => {
            publish_failed(
                &request,
                snapshots,
                cancellations,
                terminal_order,
                event_sender,
                "launchOutputUnavailable",
                format!("Cannot create launch stdout log: {error}"),
                true,
                None,
            );
            return;
        }
    };
    let stderr_file = match File::create(&stderr_path) {
        Ok(file) => file,
        Err(error) => {
            publish_failed(
                &request,
                snapshots,
                cancellations,
                terminal_order,
                event_sender,
                "launchOutputUnavailable",
                format!("Cannot create launch stderr log: {error}"),
                true,
                None,
            );
            return;
        }
    };

    let mut command = Command::new(&plan.executable);
    command
        .args(&plan.arguments)
        .current_dir(&plan.working_directory)
        .stdout(Stdio::from(stdout_file))
        .stderr(Stdio::from(stderr_file));
    for (key, value) in &plan.environment {
        command.env(key, value);
    }

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            let result = launch_result(
                &plan,
                None,
                started_at.elapsed(),
                &stdout_path,
                &stderr_path,
            );
            publish_failed(
                &request,
                snapshots,
                cancellations,
                terminal_order,
                event_sender,
                "launchSpawnFailed",
                format!("Cannot start {}: {error}", plan.executable),
                true,
                Some(result),
            );
            return;
        }
    };

    publish(
        snapshot_from_existing(
            snapshots,
            &request.operation_id,
            LaunchState::Running,
            55,
            format!("Launcher process {} is running", child.id()),
            true,
            None,
            None,
        ),
        snapshots,
        cancellations,
        terminal_order,
        event_sender,
    );

    let timeout = Duration::from_millis(plan.timeout_ms);
    loop {
        if cancelled(&request, shutdown) {
            let _ = child.kill();
            let _ = child.wait();
            let result = launch_result(
                &plan,
                None,
                started_at.elapsed(),
                &stdout_path,
                &stderr_path,
            );
            publish(
                snapshot_from_existing(
                    snapshots,
                    &request.operation_id,
                    LaunchState::Cancelled,
                    100,
                    "Launch cancelled and child process reaped",
                    false,
                    Some(result),
                    None,
                ),
                snapshots,
                cancellations,
                terminal_order,
                event_sender,
            );
            return;
        }
        if started_at.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            let result = launch_result(
                &plan,
                None,
                started_at.elapsed(),
                &stdout_path,
                &stderr_path,
            );
            publish_failed(
                &request,
                snapshots,
                cancellations,
                terminal_order,
                event_sender,
                "launchTimedOut",
                format!("The launcher exceeded {} ms", plan.timeout_ms),
                true,
                Some(result),
            );
            return;
        }
        match child.try_wait() {
            Ok(Some(status)) => {
                let result = launch_result(
                    &plan,
                    Some(status),
                    started_at.elapsed(),
                    &stdout_path,
                    &stderr_path,
                );
                if status.success() {
                    publish(
                        snapshot_from_existing(
                            snapshots,
                            &request.operation_id,
                            LaunchState::Completed,
                            100,
                            "Launcher exited and the frontend session is ready",
                            false,
                            Some(result),
                            None,
                        ),
                        snapshots,
                        cancellations,
                        terminal_order,
                        event_sender,
                    );
                } else {
                    publish_failed(
                        &request,
                        snapshots,
                        cancellations,
                        terminal_order,
                        event_sender,
                        "launchExitedNonZero",
                        format!("Launcher exited with status {status}"),
                        true,
                        Some(result),
                    );
                }
                return;
            }
            Ok(None) => thread::sleep(POLL_INTERVAL),
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                let result = launch_result(
                    &plan,
                    None,
                    started_at.elapsed(),
                    &stdout_path,
                    &stderr_path,
                );
                publish_failed(
                    &request,
                    snapshots,
                    cancellations,
                    terminal_order,
                    event_sender,
                    "launchSupervisionFailed",
                    format!("Cannot supervise launcher process: {error}"),
                    true,
                    Some(result),
                );
                return;
            }
        }
    }
}

fn prepare_filesystem(plan: &GameLaunchPlan) -> Result<(), String> {
    if !Path::new(&plan.content_path).is_file() {
        return Err(format!(
            "Configured content file does not exist: {}",
            plan.content_path
        ));
    }
    fs::create_dir_all(&plan.save_directory)
        .map_err(|error| format!("Cannot create save directory: {error}"))?;
    fs::create_dir_all(&plan.session_directory)
        .map_err(|error| format!("Cannot create session directory: {error}"))?;
    fs::create_dir_all(&plan.working_directory)
        .map_err(|error| format!("Cannot create working directory: {error}"))?;
    fs::write(
        &plan.input_profile_path,
        plan.input_profiles_json()?.as_bytes(),
    )
    .map_err(|error| format!("Cannot materialize input profiles: {error}"))?;
    fs::write(
        Path::new(&plan.session_directory).join("launch-plan.json"),
        plan.canonical_json()?.as_bytes(),
    )
    .map_err(|error| format!("Cannot materialize launch plan: {error}"))?;
    Ok(())
}

fn launch_result(
    plan: &GameLaunchPlan,
    exit_status: Option<ExitStatus>,
    duration: Duration,
    stdout_path: &Path,
    stderr_path: &Path,
) -> LaunchResult {
    let (stdout, stdout_truncated) = bounded_text(stdout_path, plan.max_output_bytes);
    let (stderr, stderr_truncated) = bounded_text(stderr_path, plan.max_output_bytes);
    let observed_path = Path::new(&plan.session_directory).join("observed-launch.json");
    LaunchResult {
        game_id: plan.game_id.clone(),
        launcher_id: plan.launcher_id.clone(),
        executable: plan.executable.clone(),
        arguments: plan.arguments.clone(),
        session_directory: plan.session_directory.clone(),
        save_directory: plan.save_directory.clone(),
        input_profile_path: plan.input_profile_path.clone(),
        observed_launch_path: observed_path
            .is_file()
            .then(|| observed_path.to_string_lossy().into_owned()),
        exit_code: exit_status.and_then(|status| status.code()),
        duration_ms: u64::try_from(duration.as_millis()).unwrap_or(u64::MAX),
        stdout,
        stderr,
        stdout_truncated,
        stderr_truncated,
    }
}

fn bounded_text(path: &Path, maximum: usize) -> (String, bool) {
    let Ok(file) = File::open(path) else {
        return (String::new(), false);
    };
    let mut bytes = Vec::new();
    let mut reader = file.take(u64::try_from(maximum.saturating_add(1)).unwrap_or(u64::MAX));
    if reader.read_to_end(&mut bytes).is_err() {
        return (String::new(), false);
    }
    let truncated = bytes.len() > maximum;
    bytes.truncate(maximum);
    (String::from_utf8_lossy(&bytes).into_owned(), truncated)
}

fn cancelled(request: &LaunchRequest, shutdown: &AtomicBool) -> bool {
    shutdown.load(Ordering::SeqCst) || request.cancellation.load(Ordering::SeqCst)
}

fn publish_cancelled(
    request: &LaunchRequest,
    snapshots: &Arc<Mutex<HashMap<String, LaunchSnapshot>>>,
    cancellations: &Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    terminal_order: &Arc<Mutex<VecDeque<String>>>,
    event_sender: &SyncSender<LaunchSnapshot>,
    message: &str,
) {
    publish(
        snapshot_from_existing(
            snapshots,
            &request.operation_id,
            LaunchState::Cancelled,
            100,
            message,
            false,
            None,
            None,
        ),
        snapshots,
        cancellations,
        terminal_order,
        event_sender,
    );
}

#[allow(clippy::too_many_arguments)]
fn publish_failed(
    request: &LaunchRequest,
    snapshots: &Arc<Mutex<HashMap<String, LaunchSnapshot>>>,
    cancellations: &Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    terminal_order: &Arc<Mutex<VecDeque<String>>>,
    event_sender: &SyncSender<LaunchSnapshot>,
    code: &str,
    message: impl Into<String>,
    retryable: bool,
    result: Option<LaunchResult>,
) {
    let message = message.into();
    publish(
        snapshot_from_existing(
            snapshots,
            &request.operation_id,
            LaunchState::Failed,
            100,
            &message,
            false,
            result,
            Some(failure(code, message.clone(), retryable)),
        ),
        snapshots,
        cancellations,
        terminal_order,
        event_sender,
    );
}

#[allow(clippy::too_many_arguments)]
fn snapshot_from_existing(
    snapshots: &Arc<Mutex<HashMap<String, LaunchSnapshot>>>,
    operation_id: &str,
    state: LaunchState,
    percent: u8,
    message: impl Into<String>,
    cancellable: bool,
    result: Option<LaunchResult>,
    error: Option<LaunchFailure>,
) -> LaunchSnapshot {
    let existing = snapshots
        .lock()
        .ok()
        .and_then(|snapshots| snapshots.get(operation_id).cloned());
    let now = now_ms();
    let mut snapshot = existing.unwrap_or_else(|| {
        LaunchSnapshot::new(operation_id, "unknown", state, percent, "", cancellable)
    });
    snapshot.state = state;
    snapshot.progress = LaunchProgress {
        completed_units: u64::from(percent),
        total_units: 100,
        percent,
        message: message.into(),
    };
    snapshot.cancellable = cancellable;
    snapshot.updated_at_ms = now;
    snapshot.result = result;
    snapshot.error = error;
    snapshot
}

fn publish(
    snapshot: LaunchSnapshot,
    snapshots: &Arc<Mutex<HashMap<String, LaunchSnapshot>>>,
    cancellations: &Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    terminal_order: &Arc<Mutex<VecDeque<String>>>,
    event_sender: &SyncSender<LaunchSnapshot>,
) {
    if let Ok(mut values) = snapshots.lock() {
        values.insert(snapshot.operation_id.clone(), snapshot.clone());
    }
    let _ = event_sender.try_send(snapshot.clone());
    if snapshot.state.is_terminal() {
        let mut evicted = Vec::new();
        if let Ok(mut order) = terminal_order.lock() {
            order.push_back(snapshot.operation_id.clone());
            while order.len() > TERMINAL_RETENTION {
                if let Some(operation_id) = order.pop_front() {
                    evicted.push(operation_id);
                }
            }
        }
        if !evicted.is_empty() {
            if let Ok(mut values) = snapshots.lock() {
                for operation_id in &evicted {
                    values.remove(operation_id);
                }
            }
            if let Ok(mut values) = cancellations.lock() {
                for operation_id in &evicted {
                    values.remove(operation_id);
                }
            }
        }
    }
}

fn response_string<T: Serialize>(result: Result<T, LaunchFailure>) -> GString {
    let response = match result {
        Ok(data) => BridgeResponse {
            schema_version: DTO_SCHEMA_VERSION,
            ok: true,
            data: Some(data),
            error: None,
        },
        Err(error) => BridgeResponse {
            schema_version: DTO_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error),
        },
    };
    let json = serde_json::to_string(&response).expect("bridge responses must serialize");
    GString::from(json.as_str())
}

fn failure(code: impl Into<String>, message: impl Into<String>, retryable: bool) -> LaunchFailure {
    LaunchFailure {
        code: code.into(),
        message: message.into(),
        retryable,
    }
}

fn lock_failure() -> LaunchFailure {
    failure(
        "launchStateUnavailable",
        "The launch runtime state is unavailable",
        true,
    )
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| u64::try_from(duration.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_state_detection_is_explicit() {
        assert!(!LaunchState::Queued.is_terminal());
        assert!(!LaunchState::Running.is_terminal());
        assert!(LaunchState::Completed.is_terminal());
        assert!(LaunchState::Failed.is_terminal());
        assert!(LaunchState::Cancelled.is_terminal());
    }

    #[test]
    fn bounded_output_never_exceeds_the_limit() {
        let directory = std::env::temp_dir().join(format!("retrolife-output-{}", now_ms()));
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join("output.txt");
        fs::write(&path, "abcdefghij").unwrap();
        let (text, truncated) = bounded_text(&path, 4);
        assert_eq!(text, "abcd");
        assert!(truncated);
        let _ = fs::remove_dir_all(directory);
    }
}
