//! Read-only Super Mario World (USA) event observation.
//!
//! Offsets describe the unmodified USA ROM, never a title-name match. Each call
//! observes WRAM immediately after one emulated frame, on the core's own thread.
//! See docs/automatic-achievements.md for pinned reverse-engineering references.

use std::collections::BTreeSet;

pub const PROFILE: &str = "super-mario-world-usa-v1";
pub const USA_SHA256: &str = "0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b";

const GAME_MODE: usize = 0x0100;
const OVERWORLD_OVERRIDE: usize = 0x0109;
const SAVE_FILE: usize = 0x010a;
const PLAYER: usize = 0x0db3;
const EXIT_RESULT: usize = 0x0dd5;
const TRANSLEVEL: usize = 0x13bf;
const PAUSED: usize = 0x13d4;
const PLAYER_ANIMATION: usize = 0x0071;
const MESSAGE_BOX: usize = 0x1426;
const FINAL_CUTSCENE: usize = 0x190d;
const REQUIRED_RAM: usize = FINAL_CUTSCENE + 1;
const YOSHI_ISLAND_STAGES: [u8; 4] = [0x29, 0x2a, 0x27, 0x26];
const KOOPALING_CASTLES: [u8; 7] = [0x25, 0x07, 0x40, 0x0e, 0x20, 0x1a, 0x34];
const BOWSER_ENTRANCES: [u8; 2] = [0x31, 0x32];

#[derive(Debug, Clone, Default)]
pub struct Observation {
    pub supported: bool,
    pub memory_available: bool,
    pub playing: bool,
    pub fps: f64,
    pub active_frames: u64,
    pub earned: BTreeSet<String>,
}

#[derive(Debug, Clone, Copy)]
struct Sample {
    mode: u8,
    override_level: u8,
    save_file: u8,
    player: u8,
    exit: u8,
    translevel: u8,
    paused: bool,
    animation: u8,
    message: u8,
    finale: u8,
}

impl Sample {
    fn read(ram: &[u8]) -> Option<Self> {
        if ram.len() < REQUIRED_RAM {
            return None;
        }
        Some(Self {
            mode: ram[GAME_MODE],
            override_level: ram[OVERWORLD_OVERRIDE],
            save_file: ram[SAVE_FILE],
            player: ram[PLAYER],
            exit: ram[EXIT_RESULT],
            translevel: ram[TRANSLEVEL],
            paused: ram[PAUSED] != 0,
            animation: ram[PLAYER_ANIMATION],
            message: ram[MESSAGE_BOX],
            finale: ram[FINAL_CUTSCENE],
        })
    }

    fn live_level(self) -> bool {
        // Demo/menu modes are not 0x14. The intro uses an overworld override.
        // Animation 9 is death. Other animations must remain observable: goal,
        // keyhole and Bowser scenes temporarily freeze normal player input.
        self.mode == 0x14
            && self.override_level == 0
            && self.save_file < 3
            && self.player < 2
            && self.translevel < 0x60
            && !self.paused
            && self.animation != 9
    }

    fn same_run(self, other: Self) -> bool {
        self.save_file == other.save_file
            && self.player == other.player
            && self.translevel == other.translevel
            && other.override_level == 0
            && !other.paused
            && other.animation != 9
    }
}

#[derive(Debug, Default)]
pub struct Detector {
    observation: Observation,
    previous_live: Option<Sample>,
    running: bool,
}

impl Detector {
    /// Start a new observation stream, discarding events from the previous game.
    pub fn start(&mut self, system: &str, sha256: &str, fps: f64) {
        let supported =
            system.eq_ignore_ascii_case("snes") && sha256.eq_ignore_ascii_case(USA_SHA256);
        self.observation = Observation {
            supported,
            fps: if fps.is_finite() && fps > 0.0 {
                fps
            } else {
                0.0
            },
            ..Observation::default()
        };
        self.previous_live = None;
        self.running = supported;
    }

    /// Observe one frame without writing to the core, ROM or saved game.
    pub fn observe(&mut self, ram: Option<&[u8]>) {
        if !self.running {
            return;
        }
        let Some(sample) = ram.and_then(Sample::read) else {
            self.reset();
            return;
        };
        self.observation.memory_available = true;
        let live = sample.live_level();
        self.observation.playing = live && sample.message == 0 && sample.animation != 0x0b;
        if self.observation.playing {
            self.observation.active_frames = self.observation.active_frames.saturating_add(1);
        }

        if let Some(previous) = self.previous_live.filter(|old| old.same_run(sample)) {
            // CODE_00C9FE writes the outcome and switches mode in the same frame.
            // 0x10 also occurs when the goal leads into the 100-star bonus game.
            // Death and Start+Select set 0x80; side exits set zero.
            let finished = previous.exit == 0
                && matches!(sample.exit, 1 | 2)
                && matches!(sample.mode, 0x0b | 0x0c | 0x10 | 0x18);
            if finished {
                if sample.exit == 1 && YOSHI_ISLAND_STAGES.contains(&sample.translevel) {
                    self.award("first_stage");
                }
                if sample.exit == 2 {
                    self.award("secret");
                }
                if sample.exit == 1 && KOOPALING_CASTLES.contains(&sample.translevel) {
                    self.award("boss");
                }
            }
            // CODE_03AC03 starts the rescue after Bowser's final defeat. Bowser
            // does not use a regular overworld exit, so it needs its own event.
            if live
                && previous.finale == 0
                && sample.finale == 1
                && sample.animation == 0x0b
                && BOWSER_ENTRANCES.contains(&sample.translevel)
            {
                self.award("finale");
            }
        }

        self.previous_live = live.then_some(sample);
    }

    /// Drop transitional evidence on reset/load discontinuities; retain awards.
    pub fn reset(&mut self) {
        self.previous_live = None;
        self.observation.memory_available = false;
        self.observation.playing = false;
    }

    /// Preserve the final snapshot for persistence, but stop accepting frames.
    pub fn stop(&mut self) {
        self.reset();
        self.running = false;
    }

    pub fn snapshot(&self) -> Observation {
        self.observation.clone()
    }

    fn award(&mut self, id: &str) {
        self.observation.earned.insert(id.to_owned());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn detector() -> Detector {
        let mut detector = Detector::default();
        detector.start("snes", USA_SHA256, 60.098812);
        detector
    }

    fn level(translevel: u8) -> Vec<u8> {
        let mut ram = vec![0; 0x20000];
        ram[GAME_MODE] = 0x14;
        ram[TRANSLEVEL] = translevel;
        ram
    }

    fn exit(ram: &mut [u8], result: u8, mode: u8) {
        ram[EXIT_RESULT] = result;
        ram[GAME_MODE] = mode;
    }

    #[test]
    fn only_supported_content_identity_enables_detection() {
        for (system, hash) in [("nes", USA_SHA256), ("snes", "Super Mario World (USA)")] {
            let mut detector = Detector::default();
            detector.start(system, hash, 60.0);
            detector.observe(Some(&level(0x29)));
            assert!(!detector.snapshot().supported);
            assert!(!detector.snapshot().memory_available);
            assert_eq!(detector.snapshot().active_frames, 0);
        }
        assert!(detector().snapshot().supported);
    }

    #[test]
    fn stage_awards_on_real_exit_not_on_goal_animation_or_repeated_snapshot() {
        for stage in YOSHI_ISLAND_STAGES {
            for exit_mode in [0x0b, 0x0c, 0x10] {
                let mut detector = detector();
                let mut ram = level(stage);
                detector.observe(Some(&ram));
                ram[0x1493] = 255;
                ram[PLAYER_ANIMATION] = 0x0d;
                detector.observe(Some(&ram));
                assert!(detector.snapshot().earned.is_empty());
                exit(&mut ram, 1, exit_mode);
                detector.observe(Some(&ram));
                detector.observe(Some(&ram));
                assert_eq!(
                    detector.snapshot().earned,
                    BTreeSet::from(["first_stage".into()])
                );
            }
        }
    }

    #[test]
    fn secret_keyhole_and_castle_exit_have_distinct_awards() {
        let mut detector = detector();
        let mut ram = level(0x15);
        detector.observe(Some(&ram));
        ram[0x1434] = 0x30;
        ram[PLAYER_ANIMATION] = 0x0b;
        detector.observe(Some(&ram));
        exit(&mut ram, 2, 0x0b);
        detector.observe(Some(&ram));
        assert_eq!(
            detector.snapshot().earned,
            BTreeSet::from(["secret".into()])
        );
        for castle in KOOPALING_CASTLES {
            let mut ram = level(castle);
            detector.observe(Some(&ram));
            exit(&mut ram, 1, 0x18);
            detector.observe(Some(&ram));
        }
        assert_eq!(
            detector.snapshot().earned,
            BTreeSet::from(["secret".into(), "boss".into()])
        );
    }

    #[test]
    fn switch_palace_fortress_house_and_normal_stage_do_not_award_koopaling() {
        for stage in [0x14, 0x08, 0x3f, 0x45, 0x0b, 0x1f, 0x35, 0x13, 0x28, 0x15] {
            let mut detector = detector();
            let mut ram = level(stage);
            detector.observe(Some(&ram));
            exit(&mut ram, 1, 0x0b);
            detector.observe(Some(&ram));
            assert!(detector.snapshot().earned.is_empty());
        }
    }

    #[test]
    fn bowser_rescue_requires_live_matching_level_and_fresh_finale() {
        for entrance in BOWSER_ENTRANCES {
            let mut detector = detector();
            let mut ram = level(entrance);
            detector.observe(Some(&ram));
            ram[FINAL_CUTSCENE] = 1;
            detector.observe(Some(&ram));
            assert!(detector.snapshot().earned.is_empty());
            ram[FINAL_CUTSCENE] = 0;
            detector.observe(Some(&ram));
            ram[FINAL_CUTSCENE] = 1;
            ram[PLAYER_ANIMATION] = 0x0b;
            detector.observe(Some(&ram));
            assert_eq!(
                detector.snapshot().earned,
                BTreeSet::from(["finale".into()])
            );
        }
        let mut detector = detector();
        let mut ram = level(0x29);
        detector.observe(Some(&ram));
        ram[FINAL_CUTSCENE] = 1;
        ram[PLAYER_ANIMATION] = 0x0b;
        detector.observe(Some(&ram));
        assert!(detector.snapshot().earned.is_empty());
    }

    #[test]
    fn menus_demos_intro_and_pause_do_not_count_as_play_or_arm_awards() {
        for mode in [0, 3, 7, 8, 9, 10, 0x0e, 0x1c, 0x27] {
            let mut detector = detector();
            let mut ram = level(0x29);
            ram[GAME_MODE] = mode;
            detector.observe(Some(&ram));
            exit(&mut ram, 1, 0x0c);
            detector.observe(Some(&ram));
            assert_eq!(detector.snapshot().active_frames, 0);
            assert!(detector.snapshot().earned.is_empty());
        }
        for field in [PAUSED, OVERWORLD_OVERRIDE] {
            let mut detector = detector();
            let mut ram = level(0x29);
            ram[field] = 1;
            detector.observe(Some(&ram));
            assert!(!detector.snapshot().playing);
            ram[field] = 0;
            exit(&mut ram, 1, 0x0c);
            detector.observe(Some(&ram));
            assert_eq!(detector.snapshot().active_frames, 0);
            assert!(detector.snapshot().earned.is_empty());
        }
    }

    #[test]
    fn death_side_exit_and_start_select_are_not_completions() {
        for (animation, result) in [(9, 0x80), (0, 0x80), (0, 0)] {
            let mut detector = detector();
            let mut ram = level(0x29);
            detector.observe(Some(&ram));
            ram[PLAYER_ANIMATION] = animation;
            detector.observe(Some(&ram));
            exit(&mut ram, result, 0x0b);
            detector.observe(Some(&ram));
            assert!(detector.snapshot().earned.is_empty());
        }
    }

    #[test]
    fn preexisting_save_progress_and_stale_outcomes_are_not_awards() {
        let mut detector = detector();
        let mut ram = level(0x29);
        ram[0x1ea2..0x1f11].fill(0xff);
        ram[0x1f2e] = 96;
        ram[EXIT_RESULT] = 1;
        detector.observe(Some(&ram));
        exit(&mut ram, 1, 0x0c);
        detector.observe(Some(&ram));
        let mut ram = level(0x31);
        ram[FINAL_CUTSCENE] = 1;
        ram[PLAYER_ANIMATION] = 0x0b;
        detector.observe(Some(&ram));
        assert!(detector.snapshot().earned.is_empty());
    }

    #[test]
    fn discontinuities_and_identity_changes_discard_evidence() {
        for field in [SAVE_FILE, PLAYER, TRANSLEVEL] {
            let mut detector = detector();
            let mut ram = level(0x29);
            detector.observe(Some(&ram));
            ram[field] += 1;
            exit(&mut ram, 1, 0x0c);
            detector.observe(Some(&ram));
            assert!(detector.snapshot().earned.is_empty());
        }
        for missing in [None, Some(&[0_u8; 16][..])] {
            let mut detector = detector();
            let mut ram = level(0x29);
            detector.observe(Some(&ram));
            detector.observe(missing);
            assert!(!detector.snapshot().memory_available);
            exit(&mut ram, 1, 0x0c);
            detector.observe(Some(&ram));
            assert!(detector.snapshot().earned.is_empty());
        }
    }

    #[test]
    fn reset_and_stop_keep_awards_but_new_start_clears_them() {
        let mut detector = detector();
        let mut ram = level(0x29);
        detector.observe(Some(&ram));
        exit(&mut ram, 1, 0x0c);
        detector.observe(Some(&ram));
        detector.reset();
        assert!(detector.snapshot().earned.contains("first_stage"));
        assert_eq!(detector.snapshot().active_frames, 1);
        let mut ram = level(0x15);
        detector.observe(Some(&ram));
        detector.reset();
        exit(&mut ram, 2, 0x0b);
        detector.observe(Some(&ram));
        assert!(!detector.snapshot().earned.contains("secret"));
        detector.stop();
        detector.observe(Some(&level(0x29)));
        assert!(!detector.snapshot().playing);
        assert!(!detector.snapshot().memory_available);
        detector.start("snes", USA_SHA256, 60.098812);
        assert!(detector.snapshot().earned.is_empty());
        assert_eq!(detector.snapshot().active_frames, 0);
    }

    #[test]
    fn invalid_fps_cannot_contaminate_progress() {
        for fps in [0.0, -1.0, f64::NAN, f64::INFINITY] {
            let mut detector = Detector::default();
            detector.start("snes", USA_SHA256, fps);
            assert_eq!(detector.snapshot().fps, 0.0);
        }
    }
}
