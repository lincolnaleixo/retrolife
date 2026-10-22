//! Local personal progress. Session time comes from emulator frames;
//! game challenges are explicitly self-reported, never inferred from time.
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

pub const MILESTONES: [&str; 4] = ["first_stage", "secret", "boss", "finale"];
pub const TIME_TARGETS: [u64; 4] = [60, 600, 1800, 3600];

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GameProgress {
    pub seconds: f64,
    pub personal: BTreeSet<String>,
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
}

impl Default for Journey {
    fn default() -> Self {
        Self {
            version: 1,
            games: BTreeMap::new(),
            cursor: 0,
            observed_game: String::new(),
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    pub seconds: u64,
    pub personal: BTreeSet<String>,
    pub earned_time: usize,
    pub game_xp: u64,
    pub total_xp: u64,
    pub level: u64,
    pub level_progress: u64,
    pub collected: usize,
    pub total_rewards: usize,
}

impl Journey {
    pub fn load(path: &Path) -> Result<Self, String> {
        let contents = match std::fs::read(path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(Self::default());
            }
            Err(_) => return Err("Personal progress could not be read.".into()),
        };
        let state: Self = serde_json::from_slice(&contents).map_err(
            |_| "Personal progress is unreadable; the original file has been preserved.",
        )?;
        if state.version != 1
            || state.games.values().any(|game| {
                !game.seconds.is_finite()
                    || game.seconds < 0.0
                    || game
                        .personal
                        .iter()
                        .any(|id| !MILESTONES.contains(&id.as_str()))
            })
        {
            return Err(
                "Unsupported personal progress; the original file has been preserved.".into(),
            );
        }
        Ok(state)
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        let bytes =
            serde_json::to_vec_pretty(self).map_err(|_| "Could not encode personal progress.")?;
        let parent = path.parent().ok_or("Missing progress directory.")?;
        std::fs::create_dir_all(parent).map_err(|_| "Could not create the progress directory.")?;
        let temporary = path.with_extension("json.tmp");
        use std::io::Write;
        let mut file =
            std::fs::File::create(&temporary).map_err(|_| "Could not save personal progress.")?;
        file.write_all(&bytes)
            .and_then(|()| file.sync_all())
            .map_err(|_| "Could not save personal progress.")?;
        std::fs::rename(temporary, path)
            .map_err(|_| "Could not finish saving personal progress.".to_owned())
    }

    pub fn begin(&mut self, id: &str) {
        self.observed_game = id.to_owned();
        self.cursor = 0;
    }

    /// Repeated polls and pauses do not add time. A new session resets the
    /// cursor explicitly, so a duplicate or decreasing sequence adds nothing.
    pub fn observe(&mut self, id: &str, sequence: u64, fps: f64) {
        if self.observed_game != id || !fps.is_finite() || fps <= 0.0 || sequence <= self.cursor {
            return;
        }
        let frames = sequence - self.cursor;
        self.cursor = sequence;
        self.games.entry(id.to_owned()).or_default().seconds += frames as f64 / fps;
    }

    pub fn confirm(&mut self, id: &str, milestone: &str, done: bool) -> Result<(), String> {
        if !MILESTONES.contains(&milestone) {
            return Err("Unknown personal challenge.".into());
        }
        let game = self.games.entry(id.to_owned()).or_default();
        if done {
            game.personal.insert(milestone.to_owned());
        } else {
            game.personal.remove(milestone);
        }
        Ok(())
    }

    pub fn summary(&self, id: &str) -> Summary {
        let game = self.games.get(id).cloned().unwrap_or_default();
        let time_count = |game: &GameProgress| {
            TIME_TARGETS
                .iter()
                .filter(|target| game.seconds >= **target as f64)
                .count()
        };
        let xp = |game: &GameProgress| {
            (time_count(game) as u64 * 50) + (game.personal.len() as u64 * 100)
        };
        let total_xp: u64 = self.games.values().map(xp).sum();
        Summary {
            seconds: game.seconds as u64,
            earned_time: time_count(&game),
            collected: time_count(&game) + game.personal.len(),
            total_rewards: 8,
            game_xp: xp(&game),
            total_xp,
            level: 1 + total_xp / 200,
            level_progress: total_xp % 200,
            personal: game.personal,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn paused_duplicate_and_failed_start_do_not_create_progress() {
        let mut state = Journey::default();
        state.observe("a", 3600, 60.0);
        assert_eq!(state.summary("a").seconds, 0);
        state.begin("a");
        state.observe("a", 3600, 60.0);
        state.observe("a", 3600, 60.0);
        state.observe("a", 3500, 60.0);
        state.observe("a", 3700, f64::NAN);
        assert_eq!(state.summary("a").seconds, 60);
        assert_eq!(state.summary("a").total_xp, 50);
        state.begin("a");
        state.observe("a", 600, 60.0);
        assert_eq!(state.summary("a").seconds, 70);
    }
    #[test]
    fn rewards_are_idempotent_and_personal_goals_can_be_corrected() {
        let mut state = Journey::default();
        state.confirm("a", "first_stage", true).unwrap();
        state.confirm("a", "first_stage", true).unwrap();
        assert_eq!(state.summary("a").total_xp, 100);
        assert_eq!(state.summary("a").earned_time, 0);
        state.confirm("a", "first_stage", false).unwrap();
        assert_eq!(state.summary("a").total_xp, 0);
        assert!(state.confirm("a", "made_up", true).is_err());
    }
    #[test]
    fn serialization_preserves_rewards_but_not_session_cursor() {
        let mut state = Journey::default();
        state.begin("a");
        state.observe("a", 36000, 60.0);
        state.confirm("b", "secret", true).unwrap();
        let restored: Journey =
            serde_json::from_str(&serde_json::to_string(&state).unwrap()).unwrap();
        assert_eq!(restored.summary("a").collected, 2);
        assert_eq!(restored.summary("a").total_xp, 200);
        assert_eq!(restored.summary("b").level, 2);
        assert_eq!(restored.cursor, 0);
    }
}
