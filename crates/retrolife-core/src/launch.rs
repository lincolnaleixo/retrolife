use crate::{
    contracts::{
        SCHEMA_VERSION, canonical_json, parse_versioned, validate_identifier, validate_text,
    },
    display_settings::GlyphFamily,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, HashSet},
    path::{Path, PathBuf},
};

pub const MAX_LAUNCH_CONFIG_BYTES: usize = 1_048_576;
pub const MAX_LAUNCHERS: usize = 128;
pub const MAX_GAME_BINDINGS: usize = 100_000;
pub const MAX_INPUT_PROFILES: usize = 128;
pub const MAX_ARGUMENTS: usize = 128;
pub const MAX_ENVIRONMENT_ENTRIES: usize = 128;
pub const MIN_LAUNCH_TIMEOUT_MS: u64 = 100;
pub const MAX_LAUNCH_TIMEOUT_MS: u64 = 86_400_000;
pub const DEFAULT_MAX_OUTPUT_BYTES: usize = 16_384;
pub const MAX_OUTPUT_BYTES: usize = 1_048_576;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ReturnPolicy {
    WaitForExit,
}

impl Default for ReturnPolicy {
    fn default() -> Self {
        Self::WaitForExit
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LaunchConfiguration {
    pub schema_version: u32,
    pub save_root: String,
    pub session_root: String,
    pub launchers: Vec<LauncherProfile>,
    pub games: Vec<GameLaunchBinding>,
    #[serde(default)]
    pub input_profiles: Vec<SystemInputProfile>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LauncherProfile {
    pub id: String,
    pub system_ids: Vec<String>,
    pub executable: String,
    #[serde(default)]
    pub arguments: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub working_directory: Option<String>,
    #[serde(default)]
    pub environment: BTreeMap<String, String>,
    #[serde(default = "default_launch_timeout_ms")]
    pub timeout_ms: u64,
    #[serde(default = "default_max_output_bytes")]
    pub max_output_bytes: usize,
    #[serde(default)]
    pub return_policy: ReturnPolicy,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct GameLaunchBinding {
    pub game_id: String,
    pub system_id: String,
    pub content_path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub launcher_id: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum LogicalAction {
    Up,
    Down,
    Left,
    Right,
    South,
    East,
    West,
    North,
    Start,
    Select,
    LeftShoulder,
    RightShoulder,
    LeftTrigger,
    RightTrigger,
    LeftStick,
    RightStick,
    Guide,
    Menu,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum PhysicalInputKind {
    Button,
    Axis,
    Hat,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum InputDirection {
    Negative,
    Positive,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub struct PhysicalInput {
    pub kind: PhysicalInputKind,
    pub code: u16,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub direction: Option<InputDirection>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub threshold_permille: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InputBinding {
    pub action: LogicalAction,
    pub input: PhysicalInput,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ControllerMatch {
    pub stable_id: String,
    pub display_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vendor_id: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub product_id: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SystemInputProfile {
    pub id: String,
    pub system_id: String,
    pub player: u8,
    pub glyph_family: GlyphFamily,
    pub controller: ControllerMatch,
    pub bindings: Vec<InputBinding>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MaterializedInputProfiles {
    pub schema_version: u32,
    pub game_id: String,
    pub system_id: String,
    pub profiles: Vec<SystemInputProfile>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct GameLaunchPlan {
    pub schema_version: u32,
    pub session_id: String,
    pub game_id: String,
    pub system_id: String,
    pub launcher_id: String,
    pub executable: String,
    pub arguments: Vec<String>,
    pub working_directory: String,
    pub environment: BTreeMap<String, String>,
    pub content_path: String,
    pub save_directory: String,
    pub session_directory: String,
    pub input_profile_path: String,
    pub input_profiles: MaterializedInputProfiles,
    pub timeout_ms: u64,
    pub max_output_bytes: usize,
    pub return_policy: ReturnPolicy,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum PreparePhase {
    Preparing,
    Ready,
    Starting,
    Running,
    Cancelled,
    Failed,
    TimedOut,
    TearingDown,
    Finished,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PrepareRequest {
    pub schema_version: u32,
    pub request_id: String,
    pub game_id: String,
    pub requested_at_ms: u64,
    pub timeout_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PrepareSession {
    pub schema_version: u32,
    pub request_id: String,
    pub game_id: String,
    pub phase: PreparePhase,
    pub generation: u64,
    pub requested_at_ms: u64,
    pub deadline_at_ms: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ready_at_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub running_at_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ended_at_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "type",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum PrepareEvent {
    Prepared { at_ms: u64 },
    StartRequested { at_ms: u64 },
    Started { at_ms: u64 },
    Cancel { at_ms: u64 },
    Fail { at_ms: u64, error: String },
    Timeout { at_ms: u64 },
    Teardown { at_ms: u64 },
    TornDown { at_ms: u64 },
}

impl LaunchConfiguration {
    pub fn normalize(mut self) -> Result<Self, String> {
        self.save_root = normalize_path_text("launch saveRoot", &self.save_root)?;
        self.session_root = normalize_path_text("launch sessionRoot", &self.session_root)?;
        for launcher in &mut self.launchers {
            launcher.normalize()?;
        }
        for game in &mut self.games {
            game.normalize()?;
        }
        for profile in &mut self.input_profiles {
            profile.normalize()?;
        }
        self.launchers.sort_by(|left, right| left.id.cmp(&right.id));
        self.games
            .sort_by(|left, right| left.game_id.cmp(&right.game_id));
        self.input_profiles.sort_by(|left, right| {
            left.system_id
                .cmp(&right.system_id)
                .then(left.player.cmp(&right.player))
                .then(left.id.cmp(&right.id))
        });
        self.validate()?;
        Ok(self)
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "Unsupported launch configuration schemaVersion {}; expected {SCHEMA_VERSION}",
                self.schema_version
            ));
        }
        normalize_path_text("launch saveRoot", &self.save_root)?;
        normalize_path_text("launch sessionRoot", &self.session_root)?;
        if self.launchers.is_empty() {
            return Err("launch configuration requires at least one launcher".to_owned());
        }
        if self.launchers.len() > MAX_LAUNCHERS {
            return Err(format!(
                "launch configuration exceeds {MAX_LAUNCHERS} launchers"
            ));
        }
        if self.games.len() > MAX_GAME_BINDINGS {
            return Err(format!(
                "launch configuration exceeds {MAX_GAME_BINDINGS} game bindings"
            ));
        }
        if self.input_profiles.len() > MAX_INPUT_PROFILES {
            return Err(format!(
                "launch configuration exceeds {MAX_INPUT_PROFILES} input profiles"
            ));
        }

        let mut launcher_ids = HashSet::with_capacity(self.launchers.len());
        for launcher in &self.launchers {
            launcher.validate()?;
            if !launcher_ids.insert(launcher.id.as_str()) {
                return Err(format!("launcher id {} is duplicated", launcher.id));
            }
        }

        let mut game_ids = HashSet::with_capacity(self.games.len());
        for game in &self.games {
            game.validate()?;
            if !game_ids.insert(game.game_id.as_str()) {
                return Err(format!("launch game id {} is duplicated", game.game_id));
            }
            if let Some(launcher_id) = &game.launcher_id {
                let launcher = self
                    .launchers
                    .iter()
                    .find(|launcher| launcher.id == *launcher_id)
                    .ok_or_else(|| {
                        format!(
                            "game {} references unknown launcher {launcher_id}",
                            game.game_id
                        )
                    })?;
                if !launcher.supports_system(&game.system_id) {
                    return Err(format!(
                        "launcher {launcher_id} does not support system {}",
                        game.system_id
                    ));
                }
            } else if !self
                .launchers
                .iter()
                .any(|launcher| launcher.supports_system(&game.system_id))
            {
                return Err(format!(
                    "game {} has no launcher for system {}",
                    game.game_id, game.system_id
                ));
            }
        }

        let mut profile_ids = HashSet::with_capacity(self.input_profiles.len());
        let mut assignments = HashSet::with_capacity(self.input_profiles.len());
        for profile in &self.input_profiles {
            profile.validate()?;
            if !profile_ids.insert(profile.id.as_str()) {
                return Err(format!("input profile id {} is duplicated", profile.id));
            }
            let assignment = (
                profile.system_id.as_str(),
                profile.player,
                profile.controller.stable_id.as_str(),
            );
            if !assignments.insert(assignment) {
                return Err(format!(
                    "controller {} is assigned more than once to {} player {}",
                    profile.controller.stable_id, profile.system_id, profile.player
                ));
            }
        }
        Ok(())
    }

    pub fn binding(&self, game_id: &str) -> Option<&GameLaunchBinding> {
        self.games.iter().find(|binding| binding.game_id == game_id)
    }

    pub fn launcher_for(&self, binding: &GameLaunchBinding) -> Option<&LauncherProfile> {
        match binding.launcher_id.as_deref() {
            Some(id) => self.launchers.iter().find(|launcher| launcher.id == id),
            None => self
                .launchers
                .iter()
                .find(|launcher| launcher.supports_system(&binding.system_id)),
        }
    }
}

impl LauncherProfile {
    fn normalize(&mut self) -> Result<(), String> {
        self.id = self.id.trim().to_owned();
        normalize_identifier_list(&mut self.system_ids);
        self.executable = normalize_path_text("launcher executable", &self.executable)?;
        for argument in &mut self.arguments {
            *argument = normalize_template_text("launcher argument", argument, 4_096)?;
        }
        if let Some(directory) = &mut self.working_directory {
            *directory = normalize_template_text("launcher workingDirectory", directory, 4_096)?;
        }
        let mut environment = BTreeMap::new();
        for (key, value) in std::mem::take(&mut self.environment) {
            environment.insert(
                key.trim().to_owned(),
                normalize_template_text("launcher environment value", &value, 16_384)?,
            );
        }
        self.environment = environment;
        self.validate()
    }

    fn validate(&self) -> Result<(), String> {
        validate_identifier("launcher id", &self.id, 128)?;
        if self.system_ids.is_empty() {
            return Err(format!("launcher {} has no systemIds", self.id));
        }
        if self.system_ids.len() > 128 {
            return Err(format!("launcher {} exceeds 128 systemIds", self.id));
        }
        let mut systems = HashSet::with_capacity(self.system_ids.len());
        for system_id in &self.system_ids {
            validate_identifier("launcher systemId", system_id, 64)?;
            if !systems.insert(system_id.as_str()) {
                return Err(format!(
                    "launcher {} systemId {} is duplicated",
                    self.id, system_id
                ));
            }
        }
        normalize_path_text("launcher executable", &self.executable)?;
        if self.arguments.len() > MAX_ARGUMENTS {
            return Err(format!(
                "launcher {} exceeds {MAX_ARGUMENTS} arguments",
                self.id
            ));
        }
        for argument in &self.arguments {
            validate_template("launcher argument", argument, 4_096)?;
        }
        if let Some(directory) = &self.working_directory {
            validate_template("launcher workingDirectory", directory, 4_096)?;
        }
        if self.environment.len() > MAX_ENVIRONMENT_ENTRIES {
            return Err(format!(
                "launcher {} exceeds {MAX_ENVIRONMENT_ENTRIES} environment entries",
                self.id
            ));
        }
        for (key, value) in &self.environment {
            validate_environment_key(key)?;
            validate_template("launcher environment value", value, 16_384)?;
        }
        if !(MIN_LAUNCH_TIMEOUT_MS..=MAX_LAUNCH_TIMEOUT_MS).contains(&self.timeout_ms) {
            return Err(format!(
                "launcher {} timeoutMs must be between {MIN_LAUNCH_TIMEOUT_MS} and {MAX_LAUNCH_TIMEOUT_MS}",
                self.id
            ));
        }
        if !(1..=MAX_OUTPUT_BYTES).contains(&self.max_output_bytes) {
            return Err(format!(
                "launcher {} maxOutputBytes must be between 1 and {MAX_OUTPUT_BYTES}",
                self.id
            ));
        }
        Ok(())
    }

    fn supports_system(&self, system_id: &str) -> bool {
        self.system_ids
            .iter()
            .any(|candidate| candidate.eq_ignore_ascii_case(system_id))
    }
}

impl GameLaunchBinding {
    fn normalize(&mut self) -> Result<(), String> {
        self.game_id = self.game_id.trim().to_owned();
        self.system_id = self.system_id.trim().to_owned();
        self.content_path = normalize_path_text("game contentPath", &self.content_path)?;
        if let Some(launcher_id) = &mut self.launcher_id {
            *launcher_id = launcher_id.trim().to_owned();
            if launcher_id.is_empty() {
                self.launcher_id = None;
            }
        }
        self.validate()
    }

    fn validate(&self) -> Result<(), String> {
        validate_identifier("launch gameId", &self.game_id, 128)?;
        validate_identifier("launch systemId", &self.system_id, 64)?;
        normalize_path_text("game contentPath", &self.content_path)?;
        if let Some(launcher_id) = &self.launcher_id {
            validate_identifier("launch launcherId", launcher_id, 128)?;
        }
        Ok(())
    }
}

impl SystemInputProfile {
    fn normalize(&mut self) -> Result<(), String> {
        self.id = self.id.trim().to_owned();
        self.system_id = self.system_id.trim().to_owned();
        self.controller.stable_id = self.controller.stable_id.trim().to_owned();
        self.controller.display_name = self.controller.display_name.trim().to_owned();
        self.bindings
            .sort_by_key(|binding| action_order(binding.action));
        self.validate()
    }

    fn validate(&self) -> Result<(), String> {
        validate_identifier("input profile id", &self.id, 128)?;
        validate_identifier("input profile systemId", &self.system_id, 64)?;
        if !(1..=4).contains(&self.player) {
            return Err(format!(
                "input profile {} player must be between 1 and 4",
                self.id
            ));
        }
        validate_identifier("controller stableId", &self.controller.stable_id, 128)?;
        validate_text("controller displayName", &self.controller.display_name, 256)?;
        if self.bindings.is_empty() {
            return Err(format!("input profile {} has no bindings", self.id));
        }
        if self.bindings.len() > 64 {
            return Err(format!("input profile {} exceeds 64 bindings", self.id));
        }
        let mut actions = HashSet::with_capacity(self.bindings.len());
        let mut physical_inputs = HashSet::with_capacity(self.bindings.len());
        for binding in &self.bindings {
            binding.input.validate()?;
            if !actions.insert(binding.action) {
                return Err(format!(
                    "input profile {} maps logical action {:?} more than once",
                    self.id, binding.action
                ));
            }
            if !physical_inputs.insert(binding.input.clone()) {
                return Err(format!(
                    "input profile {} maps one physical input more than once",
                    self.id
                ));
            }
        }
        for required in [
            LogicalAction::Up,
            LogicalAction::Down,
            LogicalAction::Left,
            LogicalAction::Right,
            LogicalAction::South,
            LogicalAction::East,
            LogicalAction::Start,
        ] {
            if !actions.contains(&required) {
                return Err(format!(
                    "input profile {} is missing required action {required:?}",
                    self.id
                ));
            }
        }
        Ok(())
    }
}

impl PhysicalInput {
    fn validate(&self) -> Result<(), String> {
        match self.kind {
            PhysicalInputKind::Button | PhysicalInputKind::Hat => {
                if self.direction.is_some() || self.threshold_permille.is_some() {
                    return Err(
                        "button and hat inputs cannot define direction or threshold".to_owned()
                    );
                }
            }
            PhysicalInputKind::Axis => {
                if self.direction.is_none() {
                    return Err("axis input requires direction".to_owned());
                }
                if !(1..=1_000).contains(&self.threshold_permille.unwrap_or(0)) {
                    return Err("axis thresholdPermille must be between 1 and 1000".to_owned());
                }
            }
        }
        Ok(())
    }
}

impl PrepareRequest {
    pub fn begin(self) -> Result<PrepareSession, String> {
        if self.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "Unsupported prepare request schemaVersion {}; expected {SCHEMA_VERSION}",
                self.schema_version
            ));
        }
        validate_identifier("prepare requestId", &self.request_id, 128)?;
        validate_identifier("prepare gameId", &self.game_id, 128)?;
        if !(MIN_LAUNCH_TIMEOUT_MS..=MAX_LAUNCH_TIMEOUT_MS).contains(&self.timeout_ms) {
            return Err(format!(
                "prepare timeoutMs must be between {MIN_LAUNCH_TIMEOUT_MS} and {MAX_LAUNCH_TIMEOUT_MS}"
            ));
        }
        let deadline_at_ms = self
            .requested_at_ms
            .checked_add(self.timeout_ms)
            .ok_or_else(|| "prepare deadline overflows the timestamp range".to_owned())?;
        Ok(PrepareSession {
            schema_version: SCHEMA_VERSION,
            request_id: self.request_id,
            game_id: self.game_id,
            phase: PreparePhase::Preparing,
            generation: 0,
            requested_at_ms: self.requested_at_ms,
            deadline_at_ms,
            ready_at_ms: None,
            running_at_ms: None,
            ended_at_ms: None,
            error: None,
        })
    }
}

impl PrepareSession {
    pub fn transition(mut self, event: PrepareEvent) -> Result<Self, String> {
        self.validate()?;
        let at_ms = event.at_ms();
        if at_ms < self.requested_at_ms {
            return Err("prepare event precedes the request".to_owned());
        }
        match event {
            PrepareEvent::Prepared { at_ms } => {
                self.require_phase(PreparePhase::Preparing, "prepared")?;
                self.require_before_deadline(at_ms)?;
                self.phase = PreparePhase::Ready;
                self.ready_at_ms = Some(at_ms);
            }
            PrepareEvent::StartRequested { at_ms } => {
                self.require_phase(PreparePhase::Ready, "startRequested")?;
                self.require_before_deadline(at_ms)?;
                self.phase = PreparePhase::Starting;
            }
            PrepareEvent::Started { at_ms } => {
                self.require_phase(PreparePhase::Starting, "started")?;
                self.require_before_deadline(at_ms)?;
                self.phase = PreparePhase::Running;
                self.running_at_ms = Some(at_ms);
            }
            PrepareEvent::Cancel { at_ms } => {
                if !matches!(
                    self.phase,
                    PreparePhase::Preparing | PreparePhase::Ready | PreparePhase::Starting
                ) {
                    return Err(format!(
                        "cannot cancel prepare session from {:?}",
                        self.phase
                    ));
                }
                self.phase = PreparePhase::Cancelled;
                self.ended_at_ms = Some(at_ms);
            }
            PrepareEvent::Fail { at_ms, error } => {
                validate_text("prepare error", &error, 1_024)?;
                if matches!(
                    self.phase,
                    PreparePhase::Finished
                        | PreparePhase::Cancelled
                        | PreparePhase::Failed
                        | PreparePhase::TimedOut
                ) {
                    return Err(format!("cannot fail prepare session from {:?}", self.phase));
                }
                self.phase = PreparePhase::Failed;
                self.error = Some(error);
                self.ended_at_ms = Some(at_ms);
            }
            PrepareEvent::Timeout { at_ms } => {
                if at_ms < self.deadline_at_ms {
                    return Err("prepare timeout occurred before deadlineAtMs".to_owned());
                }
                if !matches!(
                    self.phase,
                    PreparePhase::Preparing | PreparePhase::Ready | PreparePhase::Starting
                ) {
                    return Err(format!(
                        "cannot time out prepare session from {:?}",
                        self.phase
                    ));
                }
                self.phase = PreparePhase::TimedOut;
                self.ended_at_ms = Some(at_ms);
            }
            PrepareEvent::Teardown { at_ms } => {
                if matches!(
                    self.phase,
                    PreparePhase::Finished | PreparePhase::TearingDown
                ) {
                    return Err(format!(
                        "cannot begin teardown from prepare phase {:?}",
                        self.phase
                    ));
                }
                self.phase = PreparePhase::TearingDown;
                self.ended_at_ms = Some(at_ms);
            }
            PrepareEvent::TornDown { at_ms } => {
                self.require_phase(PreparePhase::TearingDown, "tornDown")?;
                self.phase = PreparePhase::Finished;
                self.ended_at_ms = Some(at_ms);
            }
        }
        self.generation = self
            .generation
            .checked_add(1)
            .ok_or_else(|| "prepare generation overflowed".to_owned())?;
        self.validate()?;
        Ok(self)
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "Unsupported prepare session schemaVersion {}; expected {SCHEMA_VERSION}",
                self.schema_version
            ));
        }
        validate_identifier("prepare requestId", &self.request_id, 128)?;
        validate_identifier("prepare gameId", &self.game_id, 128)?;
        if self.deadline_at_ms < self.requested_at_ms {
            return Err("prepare deadline precedes the request".to_owned());
        }
        if self.phase == PreparePhase::Failed && self.error.is_none() {
            return Err("failed prepare session requires an error".to_owned());
        }
        if let Some(error) = &self.error {
            validate_text("prepare error", error, 1_024)?;
        }
        Ok(())
    }

    fn require_phase(&self, expected: PreparePhase, event: &str) -> Result<(), String> {
        if self.phase != expected {
            return Err(format!(
                "prepare event {event} requires {expected:?}, found {:?}",
                self.phase
            ));
        }
        Ok(())
    }

    fn require_before_deadline(&self, at_ms: u64) -> Result<(), String> {
        if at_ms > self.deadline_at_ms {
            return Err("prepare deadline has elapsed; send timeout instead".to_owned());
        }
        Ok(())
    }
}

impl PrepareEvent {
    fn at_ms(&self) -> u64 {
        match self {
            Self::Prepared { at_ms }
            | Self::StartRequested { at_ms }
            | Self::Started { at_ms }
            | Self::Cancel { at_ms }
            | Self::Fail { at_ms, .. }
            | Self::Timeout { at_ms }
            | Self::Teardown { at_ms }
            | Self::TornDown { at_ms } => *at_ms,
        }
    }
}

pub fn decode_launch_configuration(json: &str) -> Result<LaunchConfiguration, String> {
    if json.len() > MAX_LAUNCH_CONFIG_BYTES {
        return Err(format!(
            "launch configuration exceeds {MAX_LAUNCH_CONFIG_BYTES} bytes"
        ));
    }
    let configuration: LaunchConfiguration = parse_versioned(json, "launch configuration")?;
    configuration.normalize()
}

pub fn normalize_launch_configuration_json(json: &str) -> Result<String, String> {
    canonical_json(&decode_launch_configuration(json)?, "launch configuration")
}

pub fn build_game_launch_plan(
    configuration: &LaunchConfiguration,
    game_id: &str,
    session_id: &str,
) -> Result<GameLaunchPlan, String> {
    configuration.validate()?;
    let game_id = game_id.trim();
    validate_identifier("launch gameId", game_id, 128)?;
    validate_identifier("launch sessionId", session_id, 128)?;
    let binding = configuration
        .binding(game_id)
        .ok_or_else(|| format!("game {game_id} has no launch binding"))?;
    let launcher = configuration.launcher_for(binding).ok_or_else(|| {
        format!(
            "game {game_id} has no launcher for system {}",
            binding.system_id
        )
    })?;

    let save_directory = join_path(
        &join_path(&configuration.save_root, &binding.system_id),
        &binding.game_id,
    );
    let session_directory = join_path(
        &join_path(&configuration.session_root, &binding.game_id),
        session_id,
    );
    let input_profile_path = join_path(&session_directory, "input-profile.json");
    let context = TemplateContext {
        game_id: &binding.game_id,
        system_id: &binding.system_id,
        content_path: &binding.content_path,
        save_directory: &save_directory,
        session_directory: &session_directory,
        input_profile_path: &input_profile_path,
    };

    let arguments = launcher
        .arguments
        .iter()
        .map(|argument| expand_template(argument, &context))
        .collect::<Result<Vec<_>, _>>()?;
    let working_directory = match launcher.working_directory.as_deref() {
        Some(template) => expand_template(template, &context)?,
        None => session_directory.clone(),
    };
    let environment = launcher
        .environment
        .iter()
        .map(|(key, value)| Ok((key.clone(), expand_template(value, &context)?)))
        .collect::<Result<BTreeMap<_, _>, String>>()?;
    let profiles = configuration
        .input_profiles
        .iter()
        .filter(|profile| profile.system_id == binding.system_id)
        .cloned()
        .collect::<Vec<_>>();

    let plan = GameLaunchPlan {
        schema_version: SCHEMA_VERSION,
        session_id: session_id.to_owned(),
        game_id: binding.game_id.clone(),
        system_id: binding.system_id.clone(),
        launcher_id: launcher.id.clone(),
        executable: launcher.executable.clone(),
        arguments,
        working_directory,
        environment,
        content_path: binding.content_path.clone(),
        save_directory,
        session_directory,
        input_profile_path,
        input_profiles: MaterializedInputProfiles {
            schema_version: SCHEMA_VERSION,
            game_id: binding.game_id.clone(),
            system_id: binding.system_id.clone(),
            profiles,
        },
        timeout_ms: launcher.timeout_ms,
        max_output_bytes: launcher.max_output_bytes,
        return_policy: launcher.return_policy,
    };
    plan.validate()?;
    Ok(plan)
}

impl GameLaunchPlan {
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "Unsupported launch plan schemaVersion {}; expected {SCHEMA_VERSION}",
                self.schema_version
            ));
        }
        validate_identifier("launch plan sessionId", &self.session_id, 128)?;
        validate_identifier("launch plan gameId", &self.game_id, 128)?;
        validate_identifier("launch plan systemId", &self.system_id, 64)?;
        validate_identifier("launch plan launcherId", &self.launcher_id, 128)?;
        normalize_path_text("launch plan executable", &self.executable)?;
        normalize_path_text("launch plan contentPath", &self.content_path)?;
        normalize_path_text("launch plan saveDirectory", &self.save_directory)?;
        normalize_path_text("launch plan sessionDirectory", &self.session_directory)?;
        normalize_path_text("launch plan inputProfilePath", &self.input_profile_path)?;
        normalize_path_text("launch plan workingDirectory", &self.working_directory)?;
        if self.arguments.len() > MAX_ARGUMENTS {
            return Err(format!("launch plan exceeds {MAX_ARGUMENTS} arguments"));
        }
        if self.arguments.iter().any(|argument| contains_nul(argument)) {
            return Err("launch plan argument contains a NUL byte".to_owned());
        }
        if !(MIN_LAUNCH_TIMEOUT_MS..=MAX_LAUNCH_TIMEOUT_MS).contains(&self.timeout_ms) {
            return Err("launch plan timeout is outside the supported range".to_owned());
        }
        if !(1..=MAX_OUTPUT_BYTES).contains(&self.max_output_bytes) {
            return Err("launch plan maxOutputBytes is outside the supported range".to_owned());
        }
        for profile in &self.input_profiles.profiles {
            profile.validate()?;
            if profile.system_id != self.system_id {
                return Err(format!(
                    "input profile {} does not match launch system {}",
                    profile.id, self.system_id
                ));
            }
        }
        Ok(())
    }

    pub fn canonical_json(&self) -> Result<String, String> {
        canonical_json(self, "launch plan")
    }

    pub fn input_profiles_json(&self) -> Result<String, String> {
        canonical_json(&self.input_profiles, "materialized input profiles")
    }
}

pub fn begin_prepare_json(json: &str) -> Result<String, String> {
    let request: PrepareRequest = parse_versioned(json, "prepare request")?;
    canonical_json(&request.begin()?, "prepare session")
}

pub fn transition_prepare_json(session_json: &str, event_json: &str) -> Result<String, String> {
    let session: PrepareSession = parse_versioned(session_json, "prepare session")?;
    let event: PrepareEvent = serde_json::from_str(event_json)
        .map_err(|error| format!("Cannot decode prepare event: {error}"))?;
    canonical_json(&session.transition(event)?, "prepare session")
}

fn default_launch_timeout_ms() -> u64 {
    300_000
}

fn default_max_output_bytes() -> usize {
    DEFAULT_MAX_OUTPUT_BYTES
}

fn normalize_identifier_list(values: &mut Vec<String>) {
    for value in values.iter_mut() {
        *value = value.trim().to_owned();
    }
    values.retain(|value| !value.is_empty());
    values.sort();
    values.dedup();
}

fn normalize_path_text(label: &str, value: &str) -> Result<String, String> {
    let value = value.trim();
    if value.is_empty() {
        return Err(format!("{label} cannot be empty"));
    }
    if value.len() > 16_384 {
        return Err(format!("{label} exceeds 16384 bytes"));
    }
    if contains_nul(value) || value.chars().any(|character| character.is_control()) {
        return Err(format!("{label} contains an unsupported character"));
    }
    Ok(value.to_owned())
}

fn normalize_template_text(label: &str, value: &str, maximum: usize) -> Result<String, String> {
    let value = value.trim().to_owned();
    validate_template(label, &value, maximum)?;
    Ok(value)
}

fn validate_template(label: &str, value: &str, maximum: usize) -> Result<(), String> {
    if value.len() > maximum {
        return Err(format!("{label} exceeds {maximum} bytes"));
    }
    if contains_nul(value) || value.chars().any(|character| character.is_control()) {
        return Err(format!("{label} contains an unsupported character"));
    }
    let mut remaining = value;
    while let Some(start) = remaining.find('{') {
        let tail = &remaining[start + 1..];
        let end = tail
            .find('}')
            .ok_or_else(|| format!("{label} has an unterminated placeholder"))?;
        let placeholder = &tail[..end];
        if !matches!(
            placeholder,
            "gameId" | "systemId" | "contentPath" | "saveDir" | "sessionDir" | "inputProfilePath"
        ) {
            return Err(format!(
                "{label} uses unknown placeholder {{{placeholder}}}"
            ));
        }
        remaining = &tail[end + 1..];
    }
    if remaining.contains('}') {
        return Err(format!("{label} has an unmatched closing brace"));
    }
    Ok(())
}

struct TemplateContext<'a> {
    game_id: &'a str,
    system_id: &'a str,
    content_path: &'a str,
    save_directory: &'a str,
    session_directory: &'a str,
    input_profile_path: &'a str,
}

fn expand_template(template: &str, context: &TemplateContext<'_>) -> Result<String, String> {
    validate_template("launch template", template, 16_384)?;
    Ok(template
        .replace("{gameId}", context.game_id)
        .replace("{systemId}", context.system_id)
        .replace("{contentPath}", context.content_path)
        .replace("{saveDir}", context.save_directory)
        .replace("{sessionDir}", context.session_directory)
        .replace("{inputProfilePath}", context.input_profile_path))
}

fn validate_environment_key(key: &str) -> Result<(), String> {
    if key.is_empty()
        || key.len() > 256
        || key.contains('=')
        || key.contains('\0')
        || key.chars().any(|character| character.is_control())
    {
        return Err("launcher environment key is invalid".to_owned());
    }
    Ok(())
}

fn contains_nul(value: &str) -> bool {
    value.as_bytes().contains(&0)
}

fn join_path(root: &str, child: &str) -> String {
    PathBuf::from(root)
        .join(Path::new(child))
        .to_string_lossy()
        .into_owned()
}

fn action_order(action: LogicalAction) -> u8 {
    match action {
        LogicalAction::Up => 0,
        LogicalAction::Down => 1,
        LogicalAction::Left => 2,
        LogicalAction::Right => 3,
        LogicalAction::South => 4,
        LogicalAction::East => 5,
        LogicalAction::West => 6,
        LogicalAction::North => 7,
        LogicalAction::Start => 8,
        LogicalAction::Select => 9,
        LogicalAction::LeftShoulder => 10,
        LogicalAction::RightShoulder => 11,
        LogicalAction::LeftTrigger => 12,
        LogicalAction::RightTrigger => 13,
        LogicalAction::LeftStick => 14,
        LogicalAction::RightStick => 15,
        LogicalAction::Guide => 16,
        LogicalAction::Menu => 17,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn binding(action: LogicalAction, code: u16) -> InputBinding {
        InputBinding {
            action,
            input: PhysicalInput {
                kind: PhysicalInputKind::Button,
                code,
                direction: None,
                threshold_permille: None,
            },
        }
    }

    fn profile() -> SystemInputProfile {
        SystemInputProfile {
            id: "fixture-snes-p1".to_owned(),
            system_id: "snes".to_owned(),
            player: 1,
            glyph_family: GlyphFamily::Generic,
            controller: ControllerMatch {
                stable_id: "fixture-controller".to_owned(),
                display_name: "Fixture Controller".to_owned(),
                vendor_id: None,
                product_id: None,
            },
            bindings: vec![
                binding(LogicalAction::Start, 6),
                binding(LogicalAction::East, 1),
                binding(LogicalAction::Up, 11),
                binding(LogicalAction::Down, 12),
                binding(LogicalAction::Left, 13),
                binding(LogicalAction::Right, 14),
                binding(LogicalAction::South, 0),
            ],
        }
    }

    fn configuration() -> LaunchConfiguration {
        LaunchConfiguration {
            schema_version: SCHEMA_VERSION,
            save_root: "/tmp/retrolife-saves".to_owned(),
            session_root: "/tmp/retrolife-sessions".to_owned(),
            launchers: vec![LauncherProfile {
                id: "fixture".to_owned(),
                system_ids: vec!["snes".to_owned()],
                executable: "/fixture/launcher".to_owned(),
                arguments: vec![
                    "--game-id".to_owned(),
                    "{gameId}".to_owned(),
                    "--content".to_owned(),
                    "{contentPath}".to_owned(),
                    "--profile".to_owned(),
                    "{inputProfilePath}".to_owned(),
                ],
                working_directory: Some("{sessionDir}".to_owned()),
                environment: BTreeMap::from([
                    ("RETROLIFE_GAME".to_owned(), "{gameId}".to_owned()),
                    ("RETROLIFE_SAVE".to_owned(), "{saveDir}".to_owned()),
                ]),
                timeout_ms: 5_000,
                max_output_bytes: 4_096,
                return_policy: ReturnPolicy::WaitForExit,
            }],
            games: vec![GameLaunchBinding {
                game_id: "chrono-trigger".to_owned(),
                system_id: "snes".to_owned(),
                content_path: "/games/chrono-trigger.sfc".to_owned(),
                launcher_id: Some("fixture".to_owned()),
            }],
            input_profiles: vec![profile()],
        }
    }

    #[test]
    fn plan_is_deterministic_and_expands_placeholders() {
        let configuration = configuration().normalize().unwrap();
        let left = build_game_launch_plan(&configuration, "chrono-trigger", "op-0001").unwrap();
        let right = build_game_launch_plan(&configuration, "chrono-trigger", "op-0001").unwrap();
        assert_eq!(left, right);
        assert_eq!(left.arguments[1], "chrono-trigger");
        assert_eq!(left.arguments[3], "/games/chrono-trigger.sfc");
        assert!(left.arguments[5].ends_with("input-profile.json"));
        assert_eq!(left.input_profiles.profiles.len(), 1);
        assert_eq!(
            left.environment.get("RETROLIFE_GAME").map(String::as_str),
            Some("chrono-trigger")
        );
    }

    #[test]
    fn missing_target_and_unknown_placeholder_are_rejected() {
        let normalized_configuration = configuration().normalize().unwrap();
        assert!(
            build_game_launch_plan(&normalized_configuration, "missing", "op-0001")
                .unwrap_err()
                .contains("no launch binding")
        );

        let mut configuration = configuration();
        configuration.launchers[0].arguments = vec!["{unknown}".to_owned()];
        assert!(
            configuration
                .normalize()
                .unwrap_err()
                .contains("unknown placeholder")
        );
    }

    #[test]
    fn input_profile_errors_are_rejected() {
        let mut configuration = configuration();
        configuration.input_profiles[0]
            .bindings
            .retain(|binding| binding.action != LogicalAction::Up);
        assert!(
            configuration
                .normalize()
                .unwrap_err()
                .contains("missing required action")
        );
    }

    #[test]
    fn prepare_state_machine_covers_success_cancel_failure_and_timeout() {
        let request = PrepareRequest {
            schema_version: SCHEMA_VERSION,
            request_id: "request-1".to_owned(),
            game_id: "chrono-trigger".to_owned(),
            requested_at_ms: 1_000,
            timeout_ms: 5_000,
        };
        let running = request
            .clone()
            .begin()
            .unwrap()
            .transition(PrepareEvent::Prepared { at_ms: 1_100 })
            .unwrap()
            .transition(PrepareEvent::StartRequested { at_ms: 1_200 })
            .unwrap()
            .transition(PrepareEvent::Started { at_ms: 1_300 })
            .unwrap();
        assert_eq!(running.phase, PreparePhase::Running);
        let finished = running
            .transition(PrepareEvent::Teardown { at_ms: 2_000 })
            .unwrap()
            .transition(PrepareEvent::TornDown { at_ms: 2_100 })
            .unwrap();
        assert_eq!(finished.phase, PreparePhase::Finished);

        let cancelled = request
            .clone()
            .begin()
            .unwrap()
            .transition(PrepareEvent::Cancel { at_ms: 1_100 })
            .unwrap();
        assert_eq!(cancelled.phase, PreparePhase::Cancelled);

        let failed = request
            .clone()
            .begin()
            .unwrap()
            .transition(PrepareEvent::Fail {
                at_ms: 1_100,
                error: "fixture failure".to_owned(),
            })
            .unwrap();
        assert_eq!(failed.phase, PreparePhase::Failed);

        let timed_out = request
            .begin()
            .unwrap()
            .transition(PrepareEvent::Timeout { at_ms: 6_000 })
            .unwrap();
        assert_eq!(timed_out.phase, PreparePhase::TimedOut);
    }

    #[test]
    fn json_contracts_are_versioned_and_canonical() {
        let json = serde_json::to_string(&configuration()).unwrap();
        let normalized = normalize_launch_configuration_json(&json).unwrap();
        let decoded = decode_launch_configuration(&normalized).unwrap();
        assert_eq!(decoded.games[0].game_id, "chrono-trigger");
        assert!(
            decode_launch_configuration(r#"{"schemaVersion":9}"#)
                .unwrap_err()
                .contains("Unsupported")
        );
    }
}
