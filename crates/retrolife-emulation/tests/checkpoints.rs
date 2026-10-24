//! End-to-end worker checks using an original, deliberately fallible libretro core.
#![cfg(any(target_os = "macos", target_os = "linux"))]
use retrolife_emulation::{
    ContentIdentity, EmulationEvent, EmulationRuntime, FrameObserver, JOYPAD_L, JOYPAD_R,
    RuntimeStatus, SessionInfo, StartRequest,
};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Default)]
struct Observation {
    resets: usize,
    frames: usize,
    pending: bool,
    earned: bool,
    wrong_thread: bool,
}
struct Observer(Arc<Mutex<Observation>>);
impl FrameObserver for Observer {
    fn session_started(&mut self, _: &ContentIdentity, _: &SessionInfo) {}
    fn frame_completed(&mut self, memory: Option<&[u8]>) {
        let mut observed = self.0.lock().unwrap();
        observed.frames += 1;
        observed.pending = true;
        observed.earned |= memory.is_some_and(|bytes| bytes[0] >= 5);
        observed.wrong_thread |= thread::current().name() != Some("retrolife-emulation");
    }
    fn reset(&mut self) {
        let mut observed = self.0.lock().unwrap();
        observed.resets += 1;
        observed.pending = false;
        observed.wrong_thread |= thread::current().name() != Some("retrolife-emulation");
    }
    fn session_stopped(&mut self) {}
}

fn wait(check: impl Fn() -> bool) {
    let start = Instant::now();
    while !check() {
        assert!(start.elapsed() < Duration::from_secs(5), "Worker timed out");
        thread::sleep(Duration::from_millis(2));
    }
}
fn started(runtime: &EmulationRuntime) {
    wait(|| {
        runtime.drain_events().iter().any(|event| match event {
            EmulationEvent::Started(_) => true,
            EmulationEvent::Failed { message } => panic!("Start failed: {message}"),
            _ => false,
        })
    });
}
fn stopped(runtime: &EmulationRuntime) {
    runtime.stop().unwrap();
    wait(|| runtime.snapshot().status == RuntimeStatus::Stopped);
}
fn operation(runtime: &EmulationRuntime, id: u64, expected: &str) {
    wait(|| {
        let state = runtime.save_states_snapshot();
        state.operation.id == id && !state.busy
    });
    let state = runtime.save_states_snapshot();
    assert_eq!(
        state.operation.status, expected,
        "{}",
        state.operation.error
    );
}
fn advance(runtime: &EmulationRuntime, frames: u64) {
    let before = runtime.snapshot().frame_sequence;
    for _ in 0..frames {
        runtime.run_frame().unwrap();
    }
    wait(|| runtime.snapshot().frame_sequence >= before + frames);
}
fn pause(runtime: &EmulationRuntime, value: bool) {
    runtime.set_paused(value).unwrap();
    wait(|| {
        runtime.snapshot().status
            == if value {
                RuntimeStatus::Paused
            } else {
                RuntimeStatus::Running
            }
    });
}
fn pixel(runtime: &EmulationRuntime) -> u8 {
    runtime.latest_video_frame().unwrap().rgba[0]
}
fn build_core(root: &Path, no_states: bool) -> PathBuf {
    let path = root.join(if no_states {
        "no-states.dylib"
    } else {
        "checkpoint.dylib"
    });
    let mut command = Command::new("cc");
    command
        .arg(if cfg!(target_os = "macos") {
            "-dynamiclib"
        } else {
            "-shared"
        })
        .arg("-fPIC")
        .arg("-std=c99");
    if no_states {
        command.arg("-DNO_STATES");
    }
    let output = command
        .arg(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/checkpoint_core.c"))
        .arg("-o")
        .arg(&path)
        .output()
        .expect("C compiler is required for the libretro fixture");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    path
}

#[test]
fn checkpoints_restore_real_core_state_persist_and_recover_from_mutating_failures() {
    let root = std::env::temp_dir().join(format!(
        "retrolife-checkpoint-worker-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir_all(&root).unwrap();
    let core = build_core(&root, false);
    let unsupported_core = build_core(&root, true);
    let rom = root.join("fixture.sfc");
    fs::write(&rom, b"original checkpoint test content").unwrap();
    let save_root = root.join("saves");
    let request = StartRequest::new(&core, &rom, &save_root, "snes", "fixture");
    let battery = save_root.join("snes/fixture/battery.srm");
    fs::create_dir_all(battery.parent().unwrap()).unwrap();
    let sentinel = [0xa5; 16];
    fs::write(&battery, sentinel).unwrap();
    let state_dir = save_root
        .join("snes/fixture/states")
        .join(format!("{:x}", Sha256::digest(fs::read(&rom).unwrap())));
    let observed = Arc::new(Mutex::new(Observation::default()));
    let runtime = EmulationRuntime::with_observer(Box::new(Observer(observed.clone()))).unwrap();
    runtime.start(request.clone()).unwrap();
    started(&runtime);
    assert!(runtime.save_states_snapshot().supported);
    advance(&runtime, 5);
    pause(&runtime, true);
    operation(&runtime, runtime.save_state(0).unwrap(), "complete");
    assert_eq!(runtime.save_state_preview(0)[0], 5);
    assert!(runtime.save_state(7).is_err());
    assert!(runtime.load_state(8).is_err());
    assert_eq!(fs::read(&battery).unwrap(), sentinel);
    pause(&runtime, false);
    advance(&runtime, 25);
    pause(&runtime, true);
    operation(&runtime, runtime.save_state(6).unwrap(), "complete");
    let frame_count = observed.lock().unwrap().frames;
    let old_sequence = runtime.snapshot().frame_sequence;
    operation(&runtime, runtime.load_state(0).unwrap(), "complete");
    assert_eq!(pixel(&runtime), 5);
    assert!(runtime.snapshot().frame_sequence > old_sequence);
    assert_eq!(runtime.save_state_preview(7)[0], 30);
    assert_eq!(runtime.snapshot().status, RuntimeStatus::Paused);
    assert_eq!(runtime.snapshot().audio_buffered_frames, 0);
    {
        let observation = observed.lock().unwrap();
        assert_eq!(
            observation.frames, frame_count,
            "Restore must not run another gameplay frame"
        );
        assert_eq!(observation.resets, 1);
        assert!(
            !observation.pending && observation.earned,
            "Discontinuity clears pending evidence, retaining earned awards"
        );
        assert!(!observation.wrong_thread);
    }
    pause(&runtime, false);
    advance(&runtime, 1);
    assert_eq!(
        pixel(&runtime),
        6,
        "The core's actual serialized counter must be restored"
    );
    stopped(&runtime);
    runtime.start(request.clone()).unwrap();
    // The worker may already finish Start before this thread polls again.
    // Stopped cleared the cache and no prior operation can cross sessions.
    assert_eq!(runtime.save_states_snapshot().operation.id, 0);
    started(&runtime);
    assert!(
        runtime.save_states_snapshot().slots[0].occupied,
        "Checkpoint survives restart"
    );
    pause(&runtime, true);
    operation(&runtime, runtime.load_state(6).unwrap(), "complete");
    assert_eq!(pixel(&runtime), 30);

    // Corrupt state fails before mutation and cannot overwrite existing Recovery.
    let slot_zero = state_dir.join("slot-0.rts");
    let valid = fs::read(&slot_zero).unwrap();
    let mut corrupt = valid.clone();
    *corrupt.last_mut().unwrap() ^= 1;
    fs::write(&slot_zero, corrupt).unwrap();
    let recovery_before = fs::read(state_dir.join("slot-7.rts")).unwrap();
    let discontinuity = runtime.save_states_snapshot().discontinuity;
    operation(&runtime, runtime.load_state(0).unwrap(), "failed");
    assert_eq!(pixel(&runtime), 30);
    assert_eq!(runtime.save_states_snapshot().discontinuity, discontinuity);
    assert_eq!(
        fs::read(state_dir.join("slot-7.rts")).unwrap(),
        recovery_before
    );
    fs::write(&slot_zero, valid).unwrap();

    // Recovery write failure prevents any unserialize call.
    let recovery = state_dir.join("slot-7.rts");
    fs::remove_file(&recovery).unwrap();
    fs::create_dir(&recovery).unwrap();
    operation(&runtime, runtime.load_state(0).unwrap(), "failed");
    assert_eq!(pixel(&runtime), 30);
    assert_eq!(runtime.save_states_snapshot().discontinuity, discontinuity);
    fs::remove_dir(&recovery).unwrap();

    // The fixture mutates its counter/SRAM before rejecting the old checkpoint.
    pause(&runtime, false);
    runtime.set_input(0, JOYPAD_L).unwrap();
    advance(&runtime, 1);
    pause(&runtime, true);
    assert_eq!(pixel(&runtime), 31);
    operation(&runtime, runtime.load_state(0).unwrap(), "failed");
    assert_eq!(pixel(&runtime), 31);
    assert!(runtime.save_states_snapshot().can_resume);
    pause(&runtime, false);
    advance(&runtime, 1);
    assert_eq!(
        pixel(&runtime),
        32,
        "Rollback must restore the real core, not only its preview"
    );

    // A failed rollback cannot resume or write corrupted SRAM on stop or Drop.
    runtime.set_input(0, JOYPAD_R).unwrap();
    advance(&runtime, 1);
    pause(&runtime, true);
    let battery_before_failure = fs::read(&battery).unwrap();
    operation(&runtime, runtime.load_state(0).unwrap(), "failed");
    assert!(!runtime.save_states_snapshot().can_resume);
    assert!(runtime.set_paused(false).is_err());
    assert!(runtime.save_state(1).is_err());
    runtime.run_frame().unwrap();
    assert_eq!(runtime.snapshot().status, RuntimeStatus::Paused);
    assert_eq!(runtime.save_state_preview(7)[0], 33);
    stopped(&runtime);
    assert_eq!(fs::read(&battery).unwrap(), battery_before_failure);
    runtime.shutdown().unwrap();
    assert_eq!(fs::read(&battery).unwrap(), battery_before_failure);

    let unsupported = EmulationRuntime::new().unwrap();
    unsupported
        .start(StartRequest::new(
            unsupported_core,
            &rom,
            root.join("unsupported-saves"),
            "snes",
            "fixture",
        ))
        .unwrap();
    started(&unsupported);
    assert!(!unsupported.save_states_snapshot().supported);
    assert!(unsupported.save_state(0).is_err());
    advance(&unsupported, 1);
    stopped(&unsupported);
    unsupported.shutdown().unwrap();
    fs::remove_dir_all(root).unwrap();
}
