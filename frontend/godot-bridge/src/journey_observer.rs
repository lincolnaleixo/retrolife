//! The worker observes game memory; Godot only receives cumulative facts.
use retrolife_core::journey::smw::Detector;
use retrolife_emulation::{ContentIdentity, FrameObserver, SessionInfo};
use std::sync::{Arc, Mutex};

pub struct JourneyObserver(pub Arc<Mutex<Detector>>);

impl FrameObserver for JourneyObserver {
    fn session_started(&mut self, content: &ContentIdentity, info: &SessionInfo) {
        if let Ok(mut detector) = self.0.lock() {
            detector.start(&content.system_id, &content.sha256, info.fps);
        }
    }

    fn frame_completed(&mut self, system_ram: Option<&[u8]>) {
        if let Ok(mut detector) = self.0.lock() {
            detector.observe(system_ram);
        }
    }

    fn reset(&mut self) {
        if let Ok(mut detector) = self.0.lock() {
            detector.reset();
        }
    }

    fn session_stopped(&mut self) {
        if let Ok(mut detector) = self.0.lock() {
            detector.stop();
        }
    }
}
