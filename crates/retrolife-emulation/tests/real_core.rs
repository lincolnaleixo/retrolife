//! Opt-in smoke test for a locally built libretro core and the original test ROM.
//!
//! Run with:
//!
//! ```text
//! RETROLIFE_TEST_CORE=/path/to/bsnes-jg_libretro.so \
//! RETROLIFE_TEST_ROM=/path/to/test.sfc \
//! cargo test -p retrolife-emulation --test real_core -- --ignored --nocapture
//! ```
//!
//! The test verifies video, battery persistence and worker-thread read-only
//! RAM observation. It does not claim that audio was audible through a device.

use retrolife_emulation::{
    ContentIdentity, EmulationEvent, EmulationRuntime, FrameObserver, RuntimeStatus, SessionInfo,
    StartRequest, VideoFrame,
};
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

static REAL_CORE_GATE: Mutex<()> = Mutex::new(());

const WAIT_STEPS: usize = 300;
const WAIT_STEP: Duration = Duration::from_millis(5);

#[derive(Default)]
struct ObservedFrames {
    content: Option<ContentIdentity>,
    frames: u64,
    resets: u32,
    stopped: bool,
    wrong_worker: bool,
    unavailable_memory: bool,
}

struct RecordingObserver(Arc<Mutex<ObservedFrames>>);

impl FrameObserver for RecordingObserver {
    fn session_started(&mut self, content: &ContentIdentity, _info: &SessionInfo) {
        let mut observation = self.0.lock().expect("observation state");
        observation.content = Some(content.clone());
        observation.wrong_worker |= thread::current().name() != Some("retrolife-emulation");
    }

    fn frame_completed(&mut self, system_ram: Option<&[u8]>) {
        let mut observation = self.0.lock().expect("observation state");
        observation.frames += 1;
        observation.wrong_worker |= thread::current().name() != Some("retrolife-emulation");
        observation.unavailable_memory |= system_ram.is_none_or(|bytes| bytes.len() != 128 * 1024);
    }

    fn reset(&mut self) {
        self.0.lock().expect("observation state").resets += 1;
    }

    fn session_stopped(&mut self) {
        self.0.lock().expect("observation state").stopped = true;
    }
}

fn wait_for_observation(state: &Mutex<ObservedFrames>, ready: impl Fn(&ObservedFrames) -> bool) {
    for _ in 0..WAIT_STEPS {
        if ready(&state.lock().expect("observation state")) {
            return;
        }
        thread::sleep(WAIT_STEP);
    }
    panic!("timed out waiting for worker observation");
}

#[test]
#[ignore = "requires RETROLIFE_TEST_CORE and RETROLIFE_TEST_ROM"]
fn configured_core_delivers_video_and_round_trips_battery_ram() {
    let _core_gate = REAL_CORE_GATE.lock().unwrap();
    let Some(core_path) = env::var_os("RETROLIFE_TEST_CORE") else {
        panic!("RETROLIFE_TEST_CORE is required for the ignored real_core test");
    };
    let Some(content_path) = env::var_os("RETROLIFE_TEST_ROM") else {
        panic!("RETROLIFE_TEST_ROM is required for the ignored real_core test");
    };

    let save_root = env::var_os("RETROLIFE_TEST_SAVE_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| env::temp_dir().join(unique_name("retrolife-real-core")));
    let generated_save_root = env::var_os("RETROLIFE_TEST_SAVE_ROOT").is_none();
    fs::create_dir_all(&save_root).expect("create test save root");
    let game_id = unique_name("fixture");
    let request = StartRequest::new(
        PathBuf::from(&core_path),
        PathBuf::from(&content_path),
        &save_root,
        "snes",
        game_id.clone(),
    );
    let battery_path = request.save_directory_for_test();

    let first_frame = {
        let observations = Arc::new(Mutex::new(ObservedFrames::default()));
        let runtime =
            EmulationRuntime::with_observer(Box::new(RecordingObserver(Arc::clone(&observations))))
                .expect("create emulation worker");
        runtime.start(request.clone()).expect("queue core start");
        let info = wait_for_started(&runtime);
        assert!(info.width > 0 && info.height > 0, "core reported no video");
        assert!(info.has_battery_ram, "fixture core reported no battery RAM");

        for _ in 0..8 {
            runtime.run_frame().expect("queue fixture frame");
        }
        let frame = wait_for_red_frame(&runtime);
        wait_for_observation(&observations, |state| state.frames == 8);
        {
            let state = observations.lock().expect("observation state");
            let content = state.content.as_ref().expect("loaded content identity");
            let loaded_bytes = fs::read(&content_path).expect("fixture bytes");
            assert_eq!(content.system_id, "snes");
            assert_eq!(
                content.sha256,
                format!("{:x}", Sha256::digest(&loaded_bytes))
            );
            assert!(
                !state.wrong_worker,
                "RAM observation left the emulation worker"
            );
            assert!(!state.unavailable_memory, "expected full SNES system RAM");
        }

        // Reset acts as an ordered worker barrier, so this proves queued frames
        // are skipped while paused without relying on a timing assumption.
        runtime.set_paused(true).expect("pause observation");
        runtime.reset().expect("reset observation baseline");
        wait_for_observation(&observations, |state| state.resets == 1);
        for _ in 0..4 {
            runtime.run_frame().expect("queue paused frame");
        }
        runtime.reset().expect("pause barrier");
        wait_for_observation(&observations, |state| state.resets == 2);
        assert_eq!(observations.lock().expect("observation state").frames, 8);
        runtime.set_paused(false).expect("resume observation");
        for _ in 0..4 {
            runtime.run_frame().expect("queue resumed frame");
        }
        wait_for_observation(&observations, |state| state.frames == 12);

        runtime.stop().expect("queue first stop");
        wait_for_stopped(&runtime);
        assert!(observations.lock().expect("observation state").stopped);
        runtime.shutdown().expect("shutdown first worker");
        frame.info.sequence
    };
    assert!(first_frame > 0);

    let first_battery = fs::read(&battery_path).expect("first battery file");
    assert!(!first_battery.is_empty(), "battery file is empty");
    assert!(
        first_battery.contains(&0x42),
        "fixture marker 0x42 was not persisted"
    );
    assert!(
        first_battery.len() > 1,
        "fixture battery is too small for sentinel"
    );

    // Change a byte the fixture does not touch. A second session must load it
    // before the fixture rewrites its known marker at offset zero.
    let mut sentinel_battery = first_battery;
    sentinel_battery[1] = 0xa5;
    fs::write(&battery_path, &sentinel_battery).expect("write sentinel battery");

    let runtime = EmulationRuntime::new().expect("create second emulation worker");
    runtime.start(request).expect("queue second core start");
    let _ = wait_for_started(&runtime);
    for _ in 0..4 {
        runtime.run_frame().expect("queue second fixture frame");
    }
    let _ = wait_for_red_frame(&runtime);
    runtime.stop().expect("queue second stop");
    wait_for_stopped(&runtime);
    runtime.shutdown().expect("shutdown second worker");

    let restored_battery = fs::read(&battery_path).expect("restored battery file");
    assert_eq!(
        restored_battery.get(1),
        Some(&0xa5),
        "battery load was not restored"
    );
    assert!(
        restored_battery.contains(&0x42),
        "fixture marker was lost after reload"
    );

    verify_battery_save_failure_is_reported(&core_path, &content_path);

    if generated_save_root {
        let _ = fs::remove_dir_all(save_root);
    }
}

fn wait_for_started(runtime: &EmulationRuntime) -> retrolife_emulation::SessionInfo {
    for _ in 0..WAIT_STEPS {
        for event in runtime.drain_events() {
            match event {
                EmulationEvent::Started(info) => return info,
                EmulationEvent::Failed { message } => panic!("core failed to start: {message}"),
                _ => {}
            }
        }
        thread::sleep(WAIT_STEP);
    }
    panic!("timed out waiting for core start")
}

fn wait_for_stopped(runtime: &EmulationRuntime) {
    for _ in 0..WAIT_STEPS {
        for event in runtime.drain_events() {
            match event {
                EmulationEvent::Stopped { .. } => return,
                EmulationEvent::Failed { message } => panic!("core failed to stop: {message}"),
                _ => {}
            }
        }
        thread::sleep(WAIT_STEP);
    }
    panic!("timed out waiting for core stop")
}

fn wait_for_failed(runtime: &EmulationRuntime) {
    for _ in 0..WAIT_STEPS {
        for event in runtime.drain_events() {
            if let EmulationEvent::Failed { .. } = event {
                return;
            }
        }
        thread::sleep(WAIT_STEP);
    }
    panic!(
        "timed out waiting for failed stop; snapshot={:?}",
        runtime.snapshot()
    )
}

fn verify_battery_save_failure_is_reported(
    core_path: &std::ffi::OsStr,
    content_path: &std::ffi::OsStr,
) {
    let save_root = env::temp_dir().join(unique_name("retrolife-save-failure"));
    let game_id = unique_name("failure-fixture");
    let request = StartRequest::new(
        PathBuf::from(core_path),
        PathBuf::from(content_path),
        &save_root,
        "snes",
        game_id,
    );
    let save_directory = request
        .save_directory_for_test()
        .parent()
        .expect("battery parent")
        .to_owned();

    let runtime = EmulationRuntime::new().expect("create save failure worker");
    runtime.start(request).expect("queue save failure start");
    let _ = wait_for_started(&runtime);
    for _ in 0..4 {
        runtime.run_frame().expect("queue save failure frame");
    }
    let _ = wait_for_red_frame(&runtime);

    // Replace the session directory with a regular file. The core still runs,
    // but the atomic battery write cannot create its destination directory.
    fs::remove_dir_all(&save_directory).expect("remove save directory");
    fs::write(&save_directory, b"occupied").expect("block save directory");

    runtime.stop().expect("queue failing stop");
    wait_for_failed(&runtime);
    assert_eq!(runtime.snapshot().status, RuntimeStatus::Failed);

    // Repair the destination and retry. The worker retained the loaded core
    // after the failed persistence attempt, so the marker must still survive.
    fs::remove_file(&save_directory).expect("remove blocking file");
    fs::create_dir_all(&save_directory).expect("restore save directory");
    runtime.stop().expect("queue retry stop");
    wait_for_stopped(&runtime);
    runtime.shutdown().expect("shutdown after retry");

    let battery = fs::read(save_directory.join("battery.srm")).expect("retried battery file");
    assert!(
        battery.contains(&0x42),
        "battery RAM was lost after retrying a failed save"
    );

    let _ = fs::remove_dir_all(save_root);
}

fn wait_for_red_frame(runtime: &EmulationRuntime) -> VideoFrame {
    let mut last_sequence = 0;
    for _ in 0..WAIT_STEPS {
        if let Some(frame) = runtime.latest_video_frame()
            && frame.info.sequence > last_sequence
        {
            last_sequence = frame.info.sequence;
            if is_red_fixture_frame(&frame) {
                return frame;
            }
        }
        for event in runtime.drain_events() {
            if let EmulationEvent::Failed { message } = event {
                panic!("core failed during frame execution: {message}");
            }
        }
        thread::sleep(WAIT_STEP);
    }
    panic!(
        "timed out waiting for red fixture video; snapshot={:?}",
        runtime.snapshot()
    )
}

fn is_red_fixture_frame(frame: &VideoFrame) -> bool {
    let pixel_count = frame.rgba.len() / 4;
    let (pixels, _) = frame.rgba.as_chunks::<4>();
    let red_pixels = pixels
        .iter()
        .filter(|pixel| pixel[0] > 160 && pixel[1] < 100 && pixel[2] < 100 && pixel[3] == 255)
        .count();
    red_pixels * 2 > pixel_count
}

fn unique_name(prefix: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("{prefix}-{}-{nanos}", std::process::id())
}

// Keep the integration test independent of private fields while deriving the
// documented save location from the same stable request components.
trait SaveDirectoryForTest {
    fn save_directory_for_test(&self) -> PathBuf;
}

impl SaveDirectoryForTest for StartRequest {
    fn save_directory_for_test(&self) -> PathBuf {
        self.save_root
            .join(&self.system_id)
            .join(&self.game_id)
            .join("battery.srm")
    }
}

#[test]
#[ignore = "requires RETROLIFE_TEST_CORE and original RETROLIFE_TEST_ROM"]
fn configured_core_persists_and_restores_exact_checkpoint_bytes() {
    let _core_gate = REAL_CORE_GATE.lock().unwrap();
    let core = env::var_os("RETROLIFE_TEST_CORE").expect("test core");
    let rom = env::var_os("RETROLIFE_TEST_ROM").expect("original test ROM");
    // Always isolated: do not use an app save location, even if another real-core
    // smoke test was configured with RETROLIFE_TEST_SAVE_ROOT.
    let root = env::temp_dir().join(unique_name("retrolife-real-checkpoint"));
    let request = StartRequest::new(
        PathBuf::from(core),
        PathBuf::from(&rom),
        &root,
        "snes",
        "checkpoint-fixture",
    );
    let battery = request.save_directory_for_test();
    let exact_rom_hash = format!("{:x}", Sha256::digest(fs::read(rom).unwrap()));
    let directory = battery
        .parent()
        .unwrap()
        .join("states")
        .join(exact_rom_hash);
    let observations = Arc::new(Mutex::new(ObservedFrames::default()));
    let runtime =
        EmulationRuntime::with_observer(Box::new(RecordingObserver(observations.clone()))).unwrap();
    runtime.start(request.clone()).unwrap();
    wait_for_started(&runtime);
    for _ in 0..8 {
        runtime.run_frame().unwrap();
    }
    let frame = wait_for_red_frame(&runtime);
    wait_for_observation(&observations, |value| value.frames == 8);
    assert!(runtime.save_states_snapshot().supported);
    let wait_operation = |id| {
        for _ in 0..WAIT_STEPS {
            let snapshot = runtime.save_states_snapshot();
            if snapshot.operation.id == id && !snapshot.busy {
                assert_eq!(
                    snapshot.operation.status, "complete",
                    "{}",
                    snapshot.operation.error
                );
                return;
            }
            thread::sleep(WAIT_STEP);
        }
        panic!("checkpoint operation timed out");
    };
    wait_operation(runtime.save_state(0).unwrap());
    let first = fs::read(directory.join("slot-0.rts")).unwrap();
    assert!(
        !battery.exists(),
        "saving a checkpoint must not write battery RAM"
    );
    for _ in 0..4 {
        runtime.run_frame().unwrap();
    }
    wait_for_observation(&observations, |value| value.frames == 12);
    runtime.set_paused(true).unwrap();
    wait_operation(runtime.load_state(0).unwrap());
    assert_eq!(runtime.snapshot().status, RuntimeStatus::Paused);
    assert_eq!(observations.lock().unwrap().resets, 1);
    let restored = runtime.latest_video_frame().expect("restored preview");
    assert!(restored.info.sequence > frame.info.sequence);
    assert_eq!(restored.rgba, frame.rgba);
    assert!(runtime.drain_audio(256).is_empty());
    wait_operation(runtime.save_state(1).unwrap());
    let second = fs::read(directory.join("slot-1.rts")).unwrap();
    let state_bytes = |bytes: &[u8]| {
        let metadata = u32::from_le_bytes(bytes[12..16].try_into().unwrap()) as usize;
        let count = u32::from_le_bytes(bytes[16..20].try_into().unwrap()) as usize;
        bytes[56 + metadata..56 + metadata + count].to_vec()
    };
    assert_eq!(
        state_bytes(&first),
        state_bytes(&second),
        "real core's full machine state must round-trip without another frame"
    );
    runtime.stop().unwrap();
    wait_for_stopped(&runtime);
    runtime.start(request).unwrap();
    wait_for_started(&runtime);
    assert!(runtime.save_states_snapshot().slots[0].compatible);
    wait_operation(runtime.load_state(0).unwrap());
    runtime.stop().unwrap();
    wait_for_stopped(&runtime);
    runtime.shutdown().unwrap();
    fs::remove_dir_all(root).unwrap();
}
