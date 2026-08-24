//! Active platform-independent domain core for the RetroLife frontend.

pub mod catalog;
mod contracts;
pub mod display_settings;
pub mod launch;

pub use catalog::{
    ArtworkKind, ArtworkReference, Catalog, CatalogSource, Game, GameAccent, MAX_CATALOG_GAMES,
    SystemSummary,
};
pub use display_settings::{
    DisplaySettings, GlyphFamily, LatencyMode, PreviewAudio, ScalingMode, ShaderPreset,
};
pub use launch::{
    ControllerMatch, GameLaunchBinding, GameLaunchPlan, InputBinding, InputDirection,
    LaunchConfiguration, LauncherProfile, LogicalAction, MAX_LAUNCH_CONFIG_BYTES,
    MaterializedInputProfiles, PhysicalInput, PhysicalInputKind, PrepareEvent, PreparePhase,
    PrepareRequest, PrepareSession, ReturnPolicy, SystemInputProfile,
};

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

pub fn default_display_settings() -> DisplaySettings {
    DisplaySettings::default()
}

pub fn default_display_settings_json() -> String {
    display_settings::default_json()
}

pub fn normalize_display_settings_json(json: &str) -> Result<String, String> {
    display_settings::normalize_json(json)
}

pub fn reference_catalog() -> &'static Catalog {
    catalog::reference_catalog()
}

pub fn reference_catalog_json() -> String {
    catalog::reference_catalog_json()
}

pub fn normalize_catalog_json(json: &str) -> Result<String, String> {
    catalog::normalize_json(json)
}

pub fn catalog_from_server_library_json(json: &str) -> Result<Catalog, String> {
    catalog::from_server_library_json(json)
}

pub fn normalize_launch_configuration_json(json: &str) -> Result<String, String> {
    launch::normalize_launch_configuration_json(json)
}

pub fn decode_launch_configuration(json: &str) -> Result<LaunchConfiguration, String> {
    launch::decode_launch_configuration(json)
}

pub fn build_game_launch_plan(
    configuration: &LaunchConfiguration,
    game_id: &str,
    session_id: &str,
) -> Result<GameLaunchPlan, String> {
    launch::build_game_launch_plan(configuration, game_id, session_id)
}
