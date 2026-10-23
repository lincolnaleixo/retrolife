//! Verified, local achievements. Only the emulator observer can award progress.
//! Version-one manual/time records remain archived, never promoted to verification.
pub mod smw;

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

pub const MILESTONES: [&str; 4] = ["first_stage", "secret", "boss", "finale"];

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LegacyProgress {
    pub seconds: f64,
    pub personal: BTreeSet<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GameProgress {
    pub seconds: f64,
    pub verified: BTreeSet<String>,
    pub profile: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub legacy: Option<LegacyProgress>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Journey {
    version: u32,
    pub games: BTreeMap<String, GameProgress>,
    #[serde(skip)]
    cursor: u64,
    #[serde(skip)]
    observed_game: String,
    #[serde(skip)]
    original_v1: Option<Vec<u8>>,
}

impl Default for Journey {
    fn default() -> Self {
        Self {
            version: 2,
            games: BTreeMap::new(),
            cursor: 0,
            observed_game: String::new(),
            original_v1: None,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Achievement {
    pub id: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub xp: u64,
    pub earned: bool,
    pub art_index: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    pub seconds: u64,
    pub achievements: Vec<Achievement>,
    pub supported: bool,
    pub detection_status: &'static str,
    pub detection_message: &'static str,
    pub legacy_preserved: bool,
    pub game_xp: u64,
    pub total_xp: u64,
    pub level: u64,
    pub level_progress: u64,
    pub collected: usize,
    pub total_rewards: usize,
}

fn valid_legacy(game: &LegacyProgress) -> bool {
    game.seconds.is_finite()
        && game.seconds >= 0.0
        && game
            .personal
            .iter()
            .all(|id| MILESTONES.contains(&id.as_str()))
}

impl Journey {
    pub fn load(path: &Path) -> Result<Self, String> {
        let contents = match std::fs::read(path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(Self::default());
            }
            Err(_) => return Err("Achievement progress could not be read.".into()),
        };
        let invalid = "Unsupported achievement progress; the original file has been preserved.";
        let raw: serde_json::Value = serde_json::from_slice(&contents).map_err(|_| invalid)?;
        let state: Self = if raw.get("version").and_then(serde_json::Value::as_u64) == Some(1) {
            #[derive(Deserialize)]
            #[serde(deny_unknown_fields)]
            struct LegacyJourney {
                version: u32,
                games: BTreeMap<String, LegacyProgress>,
            }
            let legacy: LegacyJourney = serde_json::from_slice(&contents).map_err(|_| invalid)?;
            if legacy.version != 1 || !legacy.games.values().all(valid_legacy) {
                return Err(invalid.into());
            }
            Self {
                games: legacy
                    .games
                    .into_iter()
                    .map(|(id, legacy)| {
                        (
                            id,
                            GameProgress {
                                legacy: Some(legacy),
                                ..Default::default()
                            },
                        )
                    })
                    .collect(),
                original_v1: Some(contents),
                ..Default::default()
            }
        } else {
            serde_json::from_slice(&contents).map_err(|_| invalid)?
        };
        if state.version != 2
            || state.games.values().any(|game| {
                !game.seconds.is_finite()
                    || game.seconds < 0.0
                    || game
                        .verified
                        .iter()
                        .any(|id| !MILESTONES.contains(&id.as_str()))
                    || (game.profile.as_deref() != Some(smw::PROFILE)
                        && (!game.verified.is_empty() || game.seconds > 0.0))
                    || game
                        .profile
                        .as_deref()
                        .is_some_and(|profile| profile != smw::PROFILE)
                    || game
                        .legacy
                        .as_ref()
                        .is_some_and(|legacy| !valid_legacy(legacy))
            })
        {
            return Err(invalid.into());
        }
        Ok(state)
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        use std::io::Write;
        let bytes = serde_json::to_vec_pretty(self)
            .map_err(|_| "Could not encode achievement progress.")?;
        let parent = path.parent().ok_or("Missing progress directory.")?;
        std::fs::create_dir_all(parent).map_err(|_| "Could not create the progress directory.")?;
        if let Some(original) = &self.original_v1 {
            let backup = path.with_extension("v1-backup.json");
            match std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&backup)
            {
                Ok(mut file) => {
                    if file
                        .write_all(original)
                        .and_then(|()| file.sync_all())
                        .is_err()
                    {
                        drop(file);
                        // Only this newly created, incomplete backup is removed.
                        // Never remove or replace an archive that existed already.
                        let _ = std::fs::remove_file(&backup);
                        return Err("Could not archive the original journal.".into());
                    }
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                    if std::fs::read(backup).map_err(|_| "Could not verify the journal archive.")?
                        != *original
                    {
                        return Err("A different journal archive already exists; progress was not replaced.".into());
                    }
                }
                Err(_) => return Err("Could not archive the original journal.".into()),
            }
        }
        let temporary = path.with_extension("json.tmp");
        let mut file = std::fs::File::create(&temporary)
            .map_err(|_| "Could not save achievement progress.")?;
        file.write_all(&bytes)
            .and_then(|()| file.sync_all())
            .map_err(|_| "Could not save achievement progress.")?;
        std::fs::rename(temporary, path)
            .map_err(|_| "Could not finish saving achievement progress.".to_owned())
    }

    pub fn begin(&mut self, id: &str) {
        self.observed_game = id.to_owned();
        self.cursor = 0;
    }

    /// Consume cumulative worker observations, so duplicate/slow UI polls cannot
    /// lose an award or count time twice. No API accepts a manual achievement.
    pub fn observe(&mut self, id: &str, observation: &smw::Observation) -> bool {
        if self.observed_game != id
            || !observation.supported
            || !observation.fps.is_finite()
            || observation.fps <= 0.0
        {
            return false;
        }
        let game = self.games.entry(id.to_owned()).or_default();
        game.profile = Some(smw::PROFILE.to_owned());
        if observation.active_frames > self.cursor {
            game.seconds += (observation.active_frames - self.cursor) as f64 / observation.fps;
            self.cursor = observation.active_frames;
        }
        let before = game.verified.len();
        game.verified.extend(
            observation
                .earned
                .iter()
                .filter(|id| MILESTONES.contains(&id.as_str()))
                .cloned(),
        );
        game.verified.len() > before
    }

    pub fn summary(&self, id: &str, live: Option<&smw::Observation>) -> Summary {
        let game = self.games.get(id).cloned().unwrap_or_default();
        let supported = live
            .map(|state| state.supported)
            .unwrap_or(game.profile.as_deref() == Some(smw::PROFILE) || id == smw::USA_SHA256);
        let (status, message) = match live {
            Some(state) if !state.supported => (
                "unsupported",
                "Automatic achievements are not available for this game version yet.",
            ),
            Some(state) if !state.memory_available => (
                "unavailable",
                "The emulator has not provided readable game memory. No rewards will be guessed.",
            ),
            Some(state) if state.playing => (
                "watching",
                "Watching the game. Rewards unlock automatically when you complete an objective.",
            ),
            _ if supported => (
                "waiting",
                "Play to unlock rewards automatically. Menus, demos and time alone do not earn rewards.",
            ),
            _ => (
                "unsupported",
                "Automatic achievements are not available for this game version yet.",
            ),
        };
        let total_xp: u64 = self
            .games
            .values()
            .map(|game| game.verified.len() as u64 * 100)
            .sum();
        let titles = [
            "Clear a stage on Yoshi's Island",
            "Discover a secret exit",
            "Defeat a Koopaling",
            "Rescue Peach from Bowser",
        ];
        let notes = [
            "Finish one of Yoshi's Island's four regular stages.",
            "Finish a stage using its alternate exit.",
            "Clear one of the seven Koopaling castles.",
            "Defeat Bowser and reach the ending.",
        ];
        let achievements = if supported {
            MILESTONES
                .iter()
                .enumerate()
                .map(|(index, id)| Achievement {
                    id,
                    title: titles[index],
                    description: notes[index],
                    xp: 100,
                    earned: game.verified.contains(*id),
                    art_index: index + 4,
                })
                .collect()
        } else {
            Vec::new()
        };
        Summary {
            seconds: game.seconds as u64,
            achievements,
            supported,
            detection_status: status,
            detection_message: message,
            legacy_preserved: game.legacy.is_some(),
            game_xp: if supported {
                game.verified.len() as u64 * 100
            } else {
                0
            },
            total_xp,
            level: 1 + total_xp / 200,
            level_progress: total_xp % 200,
            collected: if supported { game.verified.len() } else { 0 },
            total_rewards: if supported { 4 } else { 0 },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn observed() -> smw::Observation {
        smw::Observation {
            supported: true,
            fps: 60.0,
            memory_available: true,
            active_frames: 3600,
            earned: BTreeSet::from(["first_stage".into()]),
            ..Default::default()
        }
    }
    #[test]
    fn only_verified_events_award_xp_and_duplicate_polls_do_nothing() {
        let mut state = Journey::default();
        let event = observed();
        assert!(!state.observe("a", &event));
        state.begin("a");
        assert!(state.observe("a", &event));
        assert!(!state.observe("a", &event));
        assert_eq!(state.summary("a", None).seconds, 60);
        assert_eq!(state.summary("a", None).total_xp, 100);
        let mut time_only = event.clone();
        time_only.earned.clear();
        time_only.active_frames = 360000;
        state.observe("a", &time_only);
        assert_eq!(state.summary("a", None).total_xp, 100);
        state.begin("a");
        state.observe("a", &event);
        assert_eq!(state.summary("a", None).seconds, 6060);
        assert_eq!(state.summary("a", None).collected, 1);
    }
    #[test]
    fn unsupported_content_cannot_award_and_has_no_invented_objectives() {
        let mut state = Journey::default();
        state.begin("a");
        let event = smw::Observation {
            supported: false,
            ..observed()
        };
        assert!(!state.observe("a", &event));
        let summary = state.summary("a", Some(&event));
        assert_eq!(summary.total_xp, 0);
        assert_eq!(summary.total_rewards, 0);
        assert!(summary.achievements.is_empty());
    }
    #[test]
    fn legacy_migration_keeps_original_bytes_but_does_not_verify_manual_or_time_awards() {
        let dir = std::env::temp_dir().join(format!(
            "retrolife-journey-migration-{}",
            std::process::id()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("journey.json");
        let bytes = br#"{"version":1,"games":{"old":{"seconds":9000.0,"personal":["boss"]}}}"#;
        std::fs::write(&path, bytes).unwrap();
        let state = Journey::load(&path).unwrap();
        assert_eq!(state.summary("old", None).total_xp, 0);
        assert!(state.summary("old", None).legacy_preserved);
        state.save(&path).unwrap();
        state.save(&path).unwrap();
        assert_eq!(
            std::fs::read(path.with_extension("v1-backup.json")).unwrap(),
            bytes
        );
        let restored = Journey::load(&path).unwrap();
        assert_eq!(
            restored.games["old"].legacy.as_ref().unwrap().seconds,
            9000.0
        );
        assert!(
            restored.games["old"]
                .legacy
                .as_ref()
                .unwrap()
                .personal
                .contains("boss")
        );
        std::fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn verified_awards_survive_reload_without_session_cursor() {
        let mut state = Journey::default();
        state.begin("a");
        state.observe("a", &observed());
        let restored: Journey =
            serde_json::from_str(&serde_json::to_string(&state).unwrap()).unwrap();
        assert_eq!(restored.summary("a", None).collected, 1);
        assert_eq!(restored.cursor, 0);
        assert!(restored.observed_game.is_empty());
    }
}
